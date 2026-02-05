"""Repository rule that downloads npm packages and exposes their .d.ts files.

Unlike rules_js which reconstructs the full node_modules tree, we only need
.d.ts files for type-checking with tsgo. This is dramatically simpler:
no virtual store, no lifecycle hooks, no node_modules symlink tree.

For @types/* packages, we organize them in a typeRoots-compatible layout:
  types/<pkg_name>/  (e.g., types/node/ for @types/node)
so that TypeScript's typeRoots resolution finds them.
"""

load(":pnpm_lock_parser.bzl", "npm_tarball_url", "parse_pnpm_lock")

def _npm_types_impl(rctx):
    """Downloads npm packages from a pnpm lockfile and exposes .d.ts files."""

    # Read and parse the lockfile
    lockfile_content = rctx.read(rctx.attr.pnpm_lock)
    packages = parse_pnpm_lock(lockfile_content)

    if not packages:
        fail("No packages found in pnpm-lock.yaml. Is the file empty or malformed?")

    # Download each package and extract it
    pkg_targets = []
    for pkg_key, pkg in packages.items():
        url = npm_tarball_url(pkg.name, pkg.version)

        # Determine the final directory layout:
        # - @types/node -> types/node/ (typeRoots-compatible)
        # - other packages -> packages/<safe_name>/
        is_at_types = pkg.name.startswith("@types/")
        if is_at_types:
            type_name = pkg.name[len("@types/"):]  # "node" from "@types/node"
            final_dir = "types/" + type_name
        else:
            safe_name = pkg.name.replace("@", "_at_").replace("/", "_")
            final_dir = "packages/" + safe_name

        # Download without stripPrefix since npm tarballs use inconsistent prefixes
        raw_dir = final_dir + "_raw"
        rctx.download_and_extract(
            url = url,
            output = raw_dir,
            integrity = pkg.integrity,
        )

        # Find the actual top-level directory inside the extracted archive
        result = rctx.execute(
            ["find", raw_dir, "-maxdepth", "1", "-mindepth", "1", "-type", "d"],
            timeout = 10,
        )
        if result.return_code != 0 or not result.stdout.strip():
            continue

        extracted_dir = result.stdout.strip().split("\n")[0]

        # Move contents to the final layout
        rctx.execute(["mkdir", "-p", final_dir.rsplit("/", 1)[0]], timeout = 10)
        rctx.execute(["mv", extracted_dir, final_dir], timeout = 10)
        rctx.execute(["rm", "-rf", raw_dir], timeout = 10)

        # Check if this package has any .d.ts files
        result = rctx.execute(
            ["find", final_dir, "-name", "*.d.ts", "-type", "f"],
            timeout = 10,
        )
        has_dts = result.return_code == 0 and result.stdout.strip() != ""

        if has_dts:
            safe_name = pkg.name.replace("@", "_at_").replace("/", "_")
            pkg_targets.append(struct(
                name = pkg.name,
                safe_name = safe_name,
                dir = final_dir,
                is_at_types = is_at_types,
            ))

    # Generate the BUILD file
    build_lines = [
        'load("@rules_pnpm_tsgo//tsgo:defs.bzl", "ts_types")',
        "",
    ]

    for pkg in pkg_targets:
        # For @types packages, set typeRoots to the "types/" directory
        type_roots_attr = ""
        if pkg.is_at_types:
            type_roots_attr = '\n    type_roots = ["types"],'

        build_lines.append("""ts_types(
    name = "{safe_name}",
    srcs = glob(["{dir}/**/*.d.ts"]),{type_roots}
    visibility = ["//visibility:public"],
)""".format(
            safe_name = pkg.safe_name,
            dir = pkg.dir,
            type_roots = type_roots_attr,
        ))
        build_lines.append("")

        # Alias with original package name if it differs
        if pkg.name != pkg.safe_name:
            build_lines.append("""alias(
    name = "{alias_name}",
    actual = ":{safe_name}",
    visibility = ["//visibility:public"],
)""".format(
                alias_name = pkg.name,
                safe_name = pkg.safe_name,
            ))
            build_lines.append("")

    rctx.file("BUILD.bazel", "\n".join(build_lines))

npm_types = repository_rule(
    implementation = _npm_types_impl,
    attrs = {
        "pnpm_lock": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The pnpm-lock.yaml file.",
        ),
    },
    doc = "Downloads npm packages from a pnpm lockfile and exposes .d.ts files as ts_types targets.",
)
