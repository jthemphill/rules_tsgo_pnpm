"""Core compilation action for tsgo."""

load(":providers.bzl", "TsInfo")

def _compute_outputs(ctx, srcs):
    """Compute the expected output files from a tsgo compilation."""
    js_outputs = []
    dts_outputs = []
    map_outputs = []
    dts_map_outputs = []

    for src in srcs:
        # Strip .ts/.tsx extension
        basename = src.basename
        if basename.endswith(".tsx"):
            stem = basename[:-4]
        elif basename.endswith(".ts"):
            stem = basename[:-3]
        else:
            continue

        if ctx.attr.emit:
            js_outputs.append(ctx.actions.declare_file(stem + ".js"))
            if ctx.attr.source_map:
                map_outputs.append(ctx.actions.declare_file(stem + ".js.map"))

        if ctx.attr.declaration:
            dts_outputs.append(ctx.actions.declare_file(stem + ".d.ts"))
            if ctx.attr.declaration_map:
                dts_map_outputs.append(ctx.actions.declare_file(stem + ".d.ts.map"))

    return struct(
        js = js_outputs,
        dts = dts_outputs,
        maps = map_outputs,
        dts_maps = dts_map_outputs,
    )

def _build_tsconfig_json(srcs, out_dir, root_dir, bin_dir, opts, type_roots = []):
    """Build a tsconfig.json content string.

    All paths are relative to the execroot (the CWD at execution time).
    The tsconfig is written to the execroot at execution time via run_shell,
    so paths resolve correctly.
    """
    compiler_options = {}

    # rootDirs merges the source tree and output tree so that relative
    # imports like "../lib-a/greeting" resolve to .d.ts files in bazel-out.
    # This is the key insight that avoids the copy-to-bin tax.
    compiler_options["rootDirs"] = [".", bin_dir]

    if out_dir:
        compiler_options["outDir"] = out_dir
    if root_dir:
        compiler_options["rootDir"] = root_dir

    compiler_options["strict"] = True
    compiler_options["skipLibCheck"] = True
    compiler_options["module"] = "es2022"
    compiler_options["target"] = "es2022"
    compiler_options["moduleResolution"] = "bundler"

    if type_roots:
        compiler_options["typeRoots"] = type_roots

    if opts.declaration:
        compiler_options["declaration"] = True
    if opts.declaration_map:
        compiler_options["declarationMap"] = True
    if opts.source_map:
        compiler_options["sourceMap"] = True
    if opts.no_emit:
        compiler_options["noEmit"] = True

    files = [src.path for src in srcs]

    return json.encode({
        "compilerOptions": compiler_options,
        "files": files,
    })

def tsgo_compile_action(ctx, toolchain_info, srcs, deps, outputs):
    """Register a tsgo compilation action.

    Uses a synthetic tsconfig.json written at the execroot level so that:
    - Source file paths resolve correctly (they're relative to execroot)
    - rootDirs merges the source tree and output tree, allowing relative
      imports to find .d.ts files from deps in bazel-out
    - outDir points to the correct output location in bazel-out

    This approach avoids the copy-to-bin tax while supporting cross-package
    imports via rootDirs, following the rules_rust pattern of working directly
    with the sandbox filesystem.

    Args:
        ctx: The rule context.
        toolchain_info: TsgoToolchainInfo provider.
        srcs: List of source .ts files.
        deps: List of targets providing TsInfo.
        outputs: Struct from _compute_outputs.
    """
    tsgo_bin = toolchain_info.tsgo

    # Collect transitive declarations from deps (hierarchical depset, rules_rust pattern)
    transitive_dts = depset(transitive = [
        dep[TsInfo].transitive_declarations
        for dep in deps
        if TsInfo in dep
    ])

    all_outputs = outputs.js + outputs.dts + outputs.maps + outputs.dts_maps
    if not all_outputs:
        return outputs

    # Determine output directory from the first declared output
    out_dir = all_outputs[0].dirname

    # Compute root_dir as the common directory of all source files
    if srcs:
        dirs = [src.path.rsplit("/", 1)[0] if "/" in src.path else "." for src in srcs]
        root_dir = dirs[0]
        for d in dirs[1:]:
            root_dir = _common_prefix(root_dir, d)
        if not root_dir:
            root_dir = "."
    else:
        root_dir = "."

    # bin_dir is e.g. "bazel-out/darwin_arm64-fastbuild/bin"
    bin_dir = ctx.bin_dir.path

    # Collect typeRoots from deps' TsInfo providers.
    # type_roots in TsInfo are repo-relative (e.g., "types"), but we need
    # execroot-relative paths. For external repos, the .d.ts files live at
    # e.g. "external/_main~pnpm~npm/types/node/index.d.ts", so we need to
    # find the actual root path from the dep's declaration files.
    type_roots = []
    for dep in deps:
        if TsInfo in dep and dep[TsInfo].type_roots:
            # Get the root path for this dep's files by inspecting a .d.ts file
            dts_list = dep[TsInfo].declarations.to_list()
            if dts_list:
                # e.g. "external/_main~pnpm~npm/types/node/index.d.ts"
                # with type_root = "types", we want "external/_main~pnpm~npm/types"
                sample_path = dts_list[0].path
                for tr in dep[TsInfo].type_roots:
                    # Find the type_root directory within the sample path
                    idx = sample_path.find("/" + tr + "/")
                    if idx >= 0:
                        type_roots.append(sample_path[:idx + 1 + len(tr)])

    # Build the tsconfig content. Paths are relative to execroot.
    opts = struct(
        declaration = ctx.attr.declaration,
        declaration_map = ctx.attr.declaration_map,
        source_map = ctx.attr.source_map,
        no_emit = not ctx.attr.emit,
    )
    tsconfig_content = _build_tsconfig_json(srcs, out_dir, root_dir, bin_dir, opts, type_roots)

    # Use a unique tsconfig name to avoid collisions between targets
    tsconfig_name = "_tsgo_{}_{}.json".format(
        ctx.label.package.replace("/", "_"),
        ctx.label.name,
    )

    # All inputs: sources + transitive declarations
    inputs = depset(
        direct = srcs,
        transitive = [transitive_dts],
    )

    # Write the tsconfig at the execroot level via run_shell, then invoke tsgo.
    # This ensures all paths in the tsconfig (which are relative to execroot)
    # resolve correctly. The tsconfig is an ephemeral intermediate file.
    ctx.actions.run_shell(
        command = """\
cat > {tsconfig} << 'TSGO_TSCONFIG_EOF'
{content}
TSGO_TSCONFIG_EOF
{tsgo} --project {tsconfig}
""".format(
            tsconfig = tsconfig_name,
            content = tsconfig_content,
            tsgo = tsgo_bin.path,
        ),
        inputs = inputs,
        outputs = all_outputs,
        tools = [tsgo_bin],
        mnemonic = "TsgoCompile",
        progress_message = "Compiling TypeScript (tsgo) %{label}",
    )

    return outputs

def _common_prefix(a, b):
    """Return the longest common directory prefix of two paths."""
    parts_a = a.split("/")
    parts_b = b.split("/")
    common = []
    for i in range(min(len(parts_a), len(parts_b))):
        if parts_a[i] == parts_b[i]:
            common.append(parts_a[i])
        else:
            break
    return "/".join(common)

def ts_project_impl(ctx):
    """Implementation of the ts_project rule."""
    toolchain = ctx.toolchains["//tsgo:toolchain_type"].tsgo_info

    srcs = ctx.files.srcs
    deps = ctx.attr.deps

    outputs = _compute_outputs(ctx, srcs)
    tsgo_compile_action(ctx, toolchain, srcs, deps, outputs)

    # Build TsInfo provider
    declarations = depset(outputs.dts)
    transitive_declarations = depset(
        outputs.dts,
        transitive = [
            dep[TsInfo].transitive_declarations
            for dep in deps
            if TsInfo in dep
        ],
    )

    ts_info = TsInfo(
        declarations = declarations,
        transitive_declarations = transitive_declarations,
        js_outputs = depset(outputs.js),
        source_maps = depset(outputs.maps),
        declaration_maps = depset(outputs.dts_maps),
        srcs = depset(srcs),
        type_roots = [],
    )

    # DefaultInfo: expose JS outputs (or .d.ts if no emit)
    default_outputs = outputs.js if outputs.js else outputs.dts
    default_info = DefaultInfo(
        files = depset(default_outputs),
    )

    return [default_info, ts_info]
