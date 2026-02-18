"""Core compilation action for tsgo."""

load("@aspect_rules_js//js:libs.bzl", "js_lib_helpers")
load("@aspect_rules_js//js:providers.bzl", "JsInfo", "js_info")
load(":providers.bzl", "TsInfo")

def _compute_outputs(ctx, srcs):
    """Compute the expected output files from a tsgo compilation."""
    js_outputs = []
    dts_outputs = []
    map_outputs = []
    dts_map_outputs = []
    src_dts_copies = []

    # Compute the package directory prefix to strip from source paths,
    # preserving subdirectory structure in outputs.
    pkg_dir = ctx.label.package + "/" if ctx.label.package else ""

    for src in srcs:
        # Strip .ts/.tsx/.mts/.cts extension
        basename = src.basename
        rel_path = basename
        is_decl_src = basename.endswith(".d.ts") or basename.endswith(".d.mts") or basename.endswith(".d.cts")
        if basename.endswith(".tsx"):
            stem = basename[:-4]
        elif basename.endswith(".mts"):
            stem = basename[:-4]
        elif basename.endswith(".cts"):
            stem = basename[:-4]
        elif basename.endswith(".ts"):
            stem = basename[:-3]
        else:
            continue

        # Compute relative path from package root, preserving subdirectories.
        # e.g., for src at "packages/common/resources/aiProvider/models/types.ts"
        # in package "packages/common/resources/aiProvider", rel_stem = "models/types"
        if pkg_dir and src.path.startswith(pkg_dir):
            rel_path = src.path[len(pkg_dir):]
            if rel_path.endswith(".tsx"):
                rel_stem = rel_path[:-4]
            elif rel_path.endswith(".mts") or rel_path.endswith(".cts"):
                rel_stem = rel_path[:-4]
            elif rel_path.endswith(".ts"):
                rel_stem = rel_path[:-3]
            else:
                rel_stem = stem
        else:
            rel_stem = stem

        if is_decl_src:
            out_decl = ctx.actions.declare_file(rel_path if pkg_dir and src.path.startswith(pkg_dir) else src.basename)
            dts_outputs.append(out_decl)
            src_dts_copies.append(struct(src = src, out = out_decl))
            continue

        if ctx.attr.emit:
            js_outputs.append(ctx.actions.declare_file(rel_stem + ".js"))
            if ctx.attr.source_map:
                map_outputs.append(ctx.actions.declare_file(rel_stem + ".js.map"))

        if ctx.attr.declaration:
            dts_outputs.append(ctx.actions.declare_file(rel_stem + ".d.ts"))
            if ctx.attr.declaration_map:
                dts_map_outputs.append(ctx.actions.declare_file(rel_stem + ".d.ts.map"))

    return struct(
        js = js_outputs,
        dts = dts_outputs,
        maps = map_outputs,
        dts_maps = dts_map_outputs,
        src_dts_copies = src_dts_copies,
    )

def _build_tsconfig_json(srcs, out_dir, root_dir, bin_dir, opts, type_roots = [], extends = None, package_paths = {}, local_alias_paths = {}, extra_files = []):
    """Build a tsconfig.json content string.

    All paths are relative to the execroot (the CWD at execution time).
    The tsconfig is written to the execroot at execution time via run_shell,
    so paths resolve correctly.

    When `extends` is provided, the generated tsconfig inherits compilerOptions
    from the extended file and only overrides Bazel-specific settings.
    """
    compiler_options = {}

    # rootDirs merges the source tree and output tree so that relative
    # imports and paths mappings resolve correctly. Source files live in
    # "." but paths/outDir point to the bin dir.
    compiler_options["rootDirs"] = [".", bin_dir]

    if out_dir:
        compiler_options["outDir"] = out_dir
    if root_dir:
        compiler_options["rootDir"] = root_dir

    # When extending a user tsconfig, don't set defaults for options the
    # user's tsconfig already defines. Only set Bazel-essential overrides.
    if not extends:
        # No user tsconfig: use sensible standalone defaults
        compiler_options["strict"] = True
        compiler_options["skipLibCheck"] = True
        compiler_options["module"] = "es2022"
        compiler_options["target"] = "es2022"
        compiler_options["moduleResolution"] = "bundler"
    else:
        # With user tsconfig: only override options that conflict with Bazel.
        # skipLibCheck is always set because Bazel handles deps explicitly.
        compiler_options["skipLibCheck"] = True

        # These must be overridden to prevent Bazel conflicts
        compiler_options["incremental"] = False
        compiler_options["composite"] = False
        compiler_options["noEmit"] = False
        compiler_options["preserveSymlinks"] = False

        # Preserve package-style module resolution semantics for non-alias
        # imports (e.g. package exports and subpath exports). A "*" paths
        # remap turns package imports into raw file paths and can break
        # modules like "hono/router/trie-router".
        compiler_options["paths"] = {
            # Resolve @tryretool/* to both bin and source trees.
            # Bin first prefers built declarations from deps.
            "@tryretool/*": ["./" + bin_dir + "/packages/*", "./packages/*"],
        }

        # Preserve package-local bare import aliases (e.g. "types",
        # "agents/types") without using a global "*" remap.
        for alias, alias_paths in sorted(local_alias_paths.items()):
            compiler_options["paths"][alias] = ["./" + p for p in alias_paths]

        # Some packages (for example @lezer/python) expose types via package.json
        # "types" but TS7 can still miss them when resolving via CJS exports.
        # Pin these imports directly to their declaration entrypoint.
        if "@lezer/python" in package_paths:
            compiler_options["paths"]["@lezer/python"] = [
                "./" + package_paths["@lezer/python"] + "/dist/index.d.ts",
            ]

        # Do not map third-party npm packages through tsconfig "paths".
        # That turns package imports into filesystem aliases and can produce
        # non-portable declaration names (TS2742). Let normal node resolution
        # handle external packages.

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
    for f in extra_files:
        if f not in files:
            files.append(f)

    result = {"compilerOptions": compiler_options, "files": files}

    if extends:
        # TypeScript resolves extends paths that don't start with ./ or ../
        # as node module names. Prefix with ./ to ensure file-relative resolution
        # since the synthetic tsconfig is at the execroot root.
        if not extends.startswith("./") and not extends.startswith("../"):
            extends = "./" + extends
        result["extends"] = extends

    # Suppress project references and include globs from the parent tsconfig.
    # Bazel handles inter-package deps explicitly, and the `files` list is the
    # sole source of truth for what gets compiled.
    result["references"] = []
    result["include"] = []

    return json.encode(result)

def tsgo_compile_action(ctx, toolchain_info, srcs, deps, outputs):
    """Register a tsgo compilation action.

    Uses a synthetic tsconfig.json written at the execroot level so that:
    - Source file paths resolve correctly (they're relative to execroot)
    - rootDirs merges the source tree and output tree, allowing relative
      imports to find .d.ts files from deps in bazel-out
    - outDir points to the correct output location in bazel-out

    When a tsconfig attribute is provided, the synthetic tsconfig extends
    the user's tsconfig, inheriting project-specific compilerOptions while
    overriding only Bazel-essential settings.

    This approach avoids the copy-to-bin tax while supporting cross-package
    imports via rootDirs, following the rules_rust pattern of working directly
    with the sandbox filesystem.

    Deps can provide TsInfo (from ts_project/ts_types) or just DefaultInfo
    (from rules_js npm targets). For DefaultInfo deps, .d.ts files are collected
    and typeRoots are inferred from node_modules/@types/ paths.

    Args:
        ctx: The rule context.
        toolchain_info: TsgoToolchainInfo provider.
        srcs: List of source .ts files.
        deps: List of targets providing TsInfo or DefaultInfo.
        outputs: Struct from _compute_outputs.

    Returns:
        The same `outputs` struct passed in.
    """
    tsgo_bin = toolchain_info.tsgo

    # Collect transitive declarations from TsInfo deps (hierarchical depset, rules_rust pattern).
    # Also collect source .d.ts files so ambient declarations from deps are loaded.
    dep_transitive_decl_sets = []
    extra_tsconfig_files = []
    for dep in deps:
        if TsInfo not in dep:
            continue
        dep_decls = dep[TsInfo].transitive_declarations
        dep_transitive_decl_sets.append(dep_decls)
        for dts in dep_decls.to_list():
            if dts.path.endswith(".d.ts") or dts.path.endswith(".d.mts") or dts.path.endswith(".d.cts"):
                extra_tsconfig_files.append(dts.path)

    transitive_dts = depset(transitive = dep_transitive_decl_sets)

    all_outputs = outputs.js + outputs.dts + outputs.maps + outputs.dts_maps
    if not all_outputs:
        return outputs

    # Determine output directory.
    # Default to the package's bin directory (matching rules_ts behavior).
    # The previous implementation used the first output file's dirname, which
    # is incorrect for nested source paths (e.g. "foo/bar.ts" -> out_dir
    # ".../pkg/foo"), causing declarations and module resolution to diverge.
    if ctx.attr.out_dir:
        out_attr = ctx.attr.out_dir
        if out_attr.startswith("bazel-out/") or out_attr.startswith("/"):
            out_dir = out_attr
        elif ctx.label.package:
            if out_attr == ".":
                out_dir = ctx.bin_dir.path + "/" + ctx.label.package
            else:
                out_dir = ctx.bin_dir.path + "/" + ctx.label.package + "/" + out_attr
        elif out_attr == ".":
            out_dir = ctx.bin_dir.path
        else:
            out_dir = ctx.bin_dir.path + "/" + out_attr
    else:
        out_dir = ctx.bin_dir.path + ("/" + ctx.label.package if ctx.label.package else "")

    # Compute root_dir: use explicit attribute if set, otherwise package root
    # (matching rules_ts ts_project default root_dir=".").
    root_dir = getattr(ctx.attr, "root_dir", None)
    if root_dir == None:
        root_dir = ctx.label.package if ctx.label.package else "."
    elif root_dir == ".":
        root_dir = ctx.label.package if ctx.label.package else "."
    elif not root_dir.startswith("/") and not root_dir.startswith("bazel-"):
        if ctx.label.package:
            root_dir = ctx.label.package + "/" + root_dir

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

    # Collect files from non-TsInfo deps (e.g., rules_js npm link targets,
    # or aspect_rules_ts targets that don't provide our TsInfo).
    # We include .d.ts and .js files (and TreeArtifacts) as inputs, but
    # filter out .ts source files to prevent tsgo from re-compiling them
    # (aspect_rules_ts copy-to-bin puts .ts files in bazel-out).
    npm_files = []
    npm_type_roots = {}
    package_type_paths = {}
    for dep in deps:
        if TsInfo in dep:
            continue
        if JsInfo in dep:
            npm_files.extend(dep[JsInfo].transitive_types.to_list())
            npm_files.extend(dep[JsInfo].npm_sources.to_list())
        if DefaultInfo in dep:
            for f in dep[DefaultInfo].files.to_list():
                # Skip .ts source files (but keep .d.ts declarations).
                # TreeArtifacts (directories) are always included.
                if f.path.endswith(".ts") and not f.path.endswith(".d.ts"):
                    continue
                if f.path.endswith(".tsx"):
                    continue
                npm_files.append(f)

                # Check for @types packages in the path. rules_js uses TreeArtifacts
                # so f.path is a directory like ".../node_modules/@types/node".
                # We want the parent: ".../node_modules/@types"
                p = f.path
                seg = "/node_modules/@types/"
                idx = p.find(seg)
                if idx >= 0:
                    npm_type_roots[p[:idx + len(seg) - 1]] = True

                    # Build runtime package -> @types package root mapping.
                    # e.g. "@types/node-fetch" -> "node-fetch"
                    #      "@types/babel__core" -> "@babel/core"
                    types_rest = p[idx + len(seg):]
                    types_parts = types_rest.split("/")
                    if types_parts and types_parts[0]:
                        types_pkg = "@types/" + types_parts[0]
                        runtime_pkg = _runtime_pkg_from_types_pkg(types_pkg)
                        if runtime_pkg:
                            package_type_paths[runtime_pkg] = p[:idx + len(seg) + len(types_parts[0])]
    type_roots.extend(npm_type_roots.keys())

    # Build exact package-name mappings from declared npm dep paths.
    # Example:
    #   ".../node_modules/zod/index.d.ts" -> {"zod": ".../node_modules/zod"}
    package_paths = {}
    node_modules_segment = "/node_modules/"
    for f in npm_files:
        p = f.path
        idx = p.rfind(node_modules_segment)
        if idx < 0:
            continue
        rest = p[idx + len(node_modules_segment):]
        if not rest:
            continue
        parts = rest.split("/")
        pkg_name = ""
        if parts[0].startswith("@") and len(parts) >= 2:
            pkg_name = parts[0] + "/" + parts[1]
        elif parts[0]:
            pkg_name = parts[0]
        if not pkg_name:
            continue
        package_paths[pkg_name] = p[:idx + len(node_modules_segment) + len(pkg_name)]

    # Build package-local alias mappings from source roots so bare imports
    # like "types" or "agents/types" resolve without a global "*" paths rule.
    local_alias_paths = {}
    pkg_dir = ctx.label.package
    bin_pkg_dir = bin_dir + ("/" + pkg_dir if pkg_dir else "")
    for src in srcs:
        rel = src.path
        if pkg_dir and rel.startswith(pkg_dir + "/"):
            rel = rel[len(pkg_dir) + 1:]
        if not rel:
            continue

        if "/" in rel:
            top = rel.split("/", 1)[0]
            paths = [bin_pkg_dir + "/" + top + "/*"]
            if pkg_dir:
                paths.append(pkg_dir + "/" + top + "/*")
            else:
                paths.append(top + "/*")
            local_alias_paths[top + "/*"] = paths

            dir_paths = [bin_pkg_dir + "/" + top]
            if pkg_dir:
                dir_paths.append(pkg_dir + "/" + top)
            else:
                dir_paths.append(top)
            local_alias_paths[top] = dir_paths
        else:
            stem = rel
            if stem.endswith(".tsx"):
                stem = stem[:-4]
            elif stem.endswith(".mts") or stem.endswith(".cts"):
                stem = stem[:-4]
            elif stem.endswith(".ts"):
                stem = stem[:-3]
            if stem and stem != "index":
                if stem in package_paths:
                    continue
                paths = [bin_pkg_dir + "/" + stem]
                if pkg_dir:
                    paths.append(pkg_dir + "/" + stem)
                else:
                    paths.append(stem)
                local_alias_paths[stem] = paths

    # Also infer local aliases from same-package deps that live in subpackages.
    # Example: dep package "packages/common/types" should enable "types" imports.
    if pkg_dir:
        for dep in deps:
            dep_pkg = dep.label.package
            if not dep_pkg or not dep_pkg.startswith(pkg_dir + "/"):
                continue
            rel_pkg = dep_pkg[len(pkg_dir) + 1:]
            if not rel_pkg:
                continue
            top = rel_pkg.split("/", 1)[0]
            if top in package_paths:
                continue

            local_alias_paths[top] = [
                bin_pkg_dir + "/" + top,
                pkg_dir + "/" + top,
            ]
            local_alias_paths[top + "/*"] = [
                bin_pkg_dir + "/" + top + "/*",
                pkg_dir + "/" + top + "/*",
            ]

    # Resolve extends path for user-provided tsconfig
    extends_path = None
    tsconfig_inputs = []
    if hasattr(ctx.attr, "tsconfig") and ctx.attr.tsconfig:
        tsconfig_files = ctx.files.tsconfig
        if tsconfig_files:
            # The tsconfig file needs to be an input, and we use its
            # execroot-relative path as the extends value
            tsconfig_file = tsconfig_files[0]
            extends_path = tsconfig_file.path
            tsconfig_inputs.append(tsconfig_file)

            # Also include any transitive tsconfig deps (project references)
            if DefaultInfo in ctx.attr.tsconfig:
                for f in ctx.attr.tsconfig[DefaultInfo].files.to_list():
                    if f not in tsconfig_inputs:
                        tsconfig_inputs.append(f)

    # Build the tsconfig content. Paths are relative to execroot.
    opts = struct(
        declaration = ctx.attr.declaration,
        declaration_map = ctx.attr.declaration_map,
        source_map = ctx.attr.source_map,
        no_emit = not ctx.attr.emit,
    )

    tsconfig_content = _build_tsconfig_json(
        srcs,
        out_dir,
        root_dir,
        bin_dir,
        opts,
        type_roots,
        extends = extends_path,
        package_paths = package_paths,
        local_alias_paths = local_alias_paths,
        extra_files = extra_tsconfig_files,
    )

    # Use a unique tsconfig name to avoid collisions between targets
    tsconfig_name = "_tsgo_{}_{}.json".format(
        ctx.label.package.replace("/", "_"),
        ctx.label.name,
    )
    js_outputs_args = " ".join(["\"{}\"".format(out.path) for out in outputs.js])

    # All inputs: sources + data files + transitive declarations + npm dep files + tsconfig files
    data_files = ctx.files.data if hasattr(ctx.files, "data") else []
    inputs = depset(
        direct = srcs + data_files + npm_files + tsconfig_inputs,
        transitive = [transitive_dts],
    )

    # Write the tsconfig at the execroot level via run_shell, then invoke tsgo.
    # This ensures all paths in the tsconfig (which are relative to execroot)
    # resolve correctly. The tsconfig is an ephemeral intermediate file.
    pkg_dir = ctx.label.package
    qs_types_path = package_type_paths.get("qs", "")
    copy_decl_cmds = []
    for pair in outputs.src_dts_copies:
        copy_decl_cmds.append("mkdir -p \"$(dirname {out})\"".format(out = pair.out.path))
        copy_decl_cmds.append("cp \"$PWD/{src}\" \"$PWD/{out}\"".format(src = pair.src.path, out = pair.out.path))

    ctx.actions.run_shell(
        command = """\
if [ -n "{pkg_dir}" ]; then
  tsgo_pkg="{pkg_dir}"
  tsgo_first_nm=""
  while [ -n "$tsgo_pkg" ]; do
    tsgo_bin_nm="{bin_dir}/$tsgo_pkg/node_modules"
    if [ -d "$tsgo_bin_nm" ]; then
      mkdir -p "$tsgo_pkg"
      ln -snf "$PWD/$tsgo_bin_nm" "$tsgo_pkg/node_modules"
      if [ -z "$tsgo_first_nm" ]; then
        tsgo_first_nm="$PWD/$tsgo_bin_nm"
      fi
    fi
    if [[ "$tsgo_pkg" != *"/"* ]]; then
      break
    fi
    tsgo_pkg="${{tsgo_pkg%/*}}"
  done
  if [ -n "{qs_types_path}" ] && [ -n "$tsgo_first_nm" ]; then
    ln -snf "$PWD/{qs_types_path}" "$tsgo_first_nm/qs"
  fi
fi
{copy_decl_cmds}
cat > {tsconfig} << 'TSGO_TSCONFIG_EOF'
{content}
TSGO_TSCONFIG_EOF
{tsgo} --project {tsconfig}
for js_out in {js_outputs}; do
  if [ ! -f "$PWD/$js_out" ]; then
    continue
  fi
  perl -0777 -i -pe '
my @mocks = ($_ =~ /^jest\\.mock\\(.*?\\);\\s*$/mg);
s/^jest\\.mock\\(.*?\\);\\s*$\\n?//mg;
if (@mocks) {{
  my $block = join("", map {{ "$_\\n" }} @mocks);
  if (!s/^("use strict";\\n)/$1$block/s) {{
    $_ = $block . $_;
  }}
}}
' "$PWD/$js_out"
  tmp_js="$PWD/$js_out.tsgo_tmp"
  perl -ne '
my $line = $_;
while ($line =~ /exports\\.([A-Za-z_][A-Za-z0-9_]*)\\s*=/g) {{
  my $name = $1;
  next if $name eq "__esModule";
  $exports{{$name}} = 1;
}}
push @lines, $line;
END {{
  print @lines;
  for my $name (sort keys %exports) {{
    print "Object.defineProperty(exports, \\"$name\\", {{ enumerable: true, configurable: true, writable: true, value: exports.$name }});\\n";
  }}
}}
' "$PWD/$js_out" > "$tmp_js"
  mv "$tmp_js" "$PWD/$js_out"
done
""".format(
            pkg_dir = pkg_dir,
            qs_types_path = qs_types_path,
            bin_dir = bin_dir,
            copy_decl_cmds = "\n".join(copy_decl_cmds),
            tsconfig = tsconfig_name,
            content = tsconfig_content,
            tsgo = tsgo_bin.path,
            js_outputs = js_outputs_args,
        ),
        inputs = inputs,
        outputs = all_outputs,
        tools = [tsgo_bin],
        mnemonic = "TsgoCompile",
        progress_message = "Compiling TypeScript (tsgo) %{label}",
    )

    return outputs

def _runtime_pkg_from_types_pkg(types_pkg):
    """Map an @types package name to its runtime package name."""
    prefix = "@types/"
    if not types_pkg.startswith(prefix):
        return None
    raw = types_pkg[len(prefix):]
    if not raw:
        return None
    if "__" in raw:
        parts = raw.split("__", 1)
        if len(parts) == 2 and parts[0] and parts[1]:
            return "@{}/{}".format(parts[0], parts[1])
    return raw

def ts_project_impl(ctx):
    """Implementation of the ts_project rule.

    Args:
        ctx: The rule context.

    Returns:
        List of providers: DefaultInfo, TsInfo, and JsInfo.
    """
    toolchain = ctx.toolchains["//tsgo:toolchain_type"].tsgo_info

    srcs = ctx.files.srcs
    deps = ctx.attr.deps

    outputs = _compute_outputs(ctx, srcs)
    tsgo_compile_action(ctx, toolchain, srcs, deps, outputs)

    # Build TsInfo provider.
    # Source declaration files (.d.ts/.d.mts/.d.cts) must propagate downstream
    # even though they do not produce emitted outputs.
    src_declaration_files = []
    for src in srcs:
        if src.basename.endswith(".d.ts") or src.basename.endswith(".d.mts") or src.basename.endswith(".d.cts"):
            src_declaration_files.append(src)

    declarations = depset(direct = outputs.dts + src_declaration_files)

    # Include non-TsInfo dep files (e.g., from rules_js npm targets) in
    # transitive_declarations so downstream targets can see them.
    # These may be TreeArtifacts (directories) containing .d.ts files.
    npm_dep_files = []
    for dep in deps:
        if TsInfo in dep:
            continue
        if DefaultInfo in dep:
            npm_dep_files.extend(dep[DefaultInfo].files.to_list())

    transitive_declarations = depset(
        outputs.dts + src_declaration_files + npm_dep_files,
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

    data_files = ctx.files.data
    runtime_data_files = data_files
    js_runtime_data_files = []
    for data_file in data_files:
        # rules_js cannot copy source files from a different package via JsInfo
        # direct sources. Keep same-package source assets (like local JSON files),
        # and allow generated files (already in bazel-out).
        if data_file.is_source and data_file.owner.package != ctx.label.package:
            continue
        js_runtime_data_files.append(data_file)

    default_outputs = outputs.js if outputs.js else (outputs.dts if outputs.dts else src_declaration_files)

    # DefaultInfo: expose JS outputs (or .d.ts if no emit). Runtime data files
    # are carried in default runfiles so downstream js_binary/js_test targets
    # pick them up without treating them as cross-package source files.
    default_info = DefaultInfo(
        files = depset(default_outputs),
        runfiles = ctx.runfiles(files = default_outputs + runtime_data_files),
    )

    # Gather transitive JS info for rules_js interoperability.
    # This lets js_library, jest_test, and other rules_js targets
    # depend on tsgo ts_project targets.
    output_sources_depset = depset(outputs.js + js_runtime_data_files)
    output_types_depset = depset(outputs.dts + src_declaration_files)
    transitive_sources = js_lib_helpers.gather_transitive_sources(outputs.js + js_runtime_data_files, ctx.attr.deps)
    transitive_types = js_lib_helpers.gather_transitive_types(outputs.dts + src_declaration_files, ctx.attr.deps)
    npm_sources = js_lib_helpers.gather_npm_sources(srcs = ctx.attr.srcs + ctx.attr.data, deps = ctx.attr.deps)
    npm_package_store_infos = js_lib_helpers.gather_npm_package_store_infos(
        targets = ctx.attr.srcs + ctx.attr.deps + ctx.attr.data,
    )
    js_info_provider = js_info(
        target = ctx.label,
        sources = output_sources_depset,
        types = output_types_depset,
        transitive_sources = transitive_sources,
        transitive_types = transitive_types,
        npm_sources = npm_sources,
        npm_package_store_infos = npm_package_store_infos,
    )

    return [default_info, ts_info, js_info_provider]
