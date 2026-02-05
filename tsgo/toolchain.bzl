"""Toolchain definitions for tsgo."""

TsgoToolchainInfo = provider(
    doc = "Information about the tsgo compiler toolchain.",
    fields = {
        "tsgo": "File: the tsgo executable",
        "version": "string: tsgo version",
    },
)

def _tsgo_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        tsgo_info = TsgoToolchainInfo(
            tsgo = ctx.executable.tsgo,
            version = ctx.attr.version,
        ),
    )
    return [toolchain_info]

tsgo_toolchain = rule(
    implementation = _tsgo_toolchain_impl,
    attrs = {
        "tsgo": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "The tsgo compiler binary.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The tsgo version.",
        ),
    },
    doc = "Declares a tsgo compiler toolchain.",
)
