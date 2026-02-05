"""Rule for wrapping .d.ts files into a TsInfo provider."""

load(":providers.bzl", "TsInfo")

def _ts_types_impl(ctx):
    dts_files = []
    for src in ctx.files.srcs:
        if src.path.endswith(".d.ts"):
            dts_files.append(src)

    declarations = depset(dts_files)
    transitive_declarations = depset(
        dts_files,
        transitive = [
            dep[TsInfo].transitive_declarations
            for dep in ctx.attr.deps
            if TsInfo in dep
        ],
    )

    # Collect type_roots from this target and deps
    type_roots = list(ctx.attr.type_roots)
    for dep in ctx.attr.deps:
        if TsInfo in dep:
            type_roots.extend(dep[TsInfo].type_roots)

    return [
        DefaultInfo(files = declarations),
        TsInfo(
            declarations = declarations,
            transitive_declarations = transitive_declarations,
            js_outputs = depset(),
            source_maps = depset(),
            declaration_maps = depset(),
            srcs = depset(),
            type_roots = type_roots,
        ),
    ]

ts_types = rule(
    implementation = _ts_types_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".d.ts"],
            doc = "Type declaration files (.d.ts).",
        ),
        "deps": attr.label_list(
            doc = "Other ts_types or ts_project targets this depends on.",
        ),
        "type_roots": attr.string_list(
            default = [],
            doc = "Paths to include as typeRoots in tsconfig (for @types packages).",
        ),
    },
    doc = "Wraps .d.ts files into a TsInfo provider for use as ts_project deps.",
)
