"""Rule for wrapping tsconfig.json files into a Bazel target.

This provides API compatibility with aspect_rules_ts's ts_config rule,
allowing BUILD files to define tsconfig targets that can be referenced
by ts_project rules.
"""

def _ts_config_impl(ctx):
    """Implementation of the ts_config rule."""
    src = ctx.file.src

    # Collect transitive tsconfig files from deps
    transitive_files = []
    for dep in ctx.attr.deps:
        if DefaultInfo in dep:
            transitive_files.append(dep[DefaultInfo].files)

    all_files = depset(
        direct = [src],
        transitive = transitive_files,
    )

    return [DefaultInfo(files = all_files)]

ts_config = rule(
    implementation = _ts_config_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".json"],
            mandatory = True,
            doc = "The tsconfig.json file.",
        ),
        "deps": attr.label_list(
            default = [],
            doc = "Other ts_config targets referenced via project references or extends.",
        ),
    },
    doc = """Wraps a tsconfig.json file as a Bazel target.

Provides API compatibility with aspect_rules_ts ts_config.
The tsconfig can be referenced by ts_project targets via the tsconfig attribute.
""",
)
