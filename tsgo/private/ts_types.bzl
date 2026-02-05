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

    return [
        DefaultInfo(files = declarations),
        TsInfo(
            declarations = declarations,
            transitive_declarations = transitive_declarations,
            js_outputs = depset(),
            source_maps = depset(),
            declaration_maps = depset(),
            srcs = depset(),
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
    },
    doc = "Wraps .d.ts files into a TsInfo provider for use as ts_project deps.",
)
