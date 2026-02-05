"""Repository rules to download tsgo and register toolchains."""

# Platform mapping: (Bazel os, Bazel cpu) -> npm package suffix
_PLATFORMS = {
    "darwin_arm64": struct(
        os = "macos",
        cpu = "arm64",
        npm_suffix = "darwin-arm64",
    ),
    "darwin_x86_64": struct(
        os = "macos",
        cpu = "x86_64",
        npm_suffix = "darwin-x64",
    ),
    "linux_x86_64": struct(
        os = "linux",
        cpu = "x86_64",
        npm_suffix = "linux-x64",
    ),
    "linux_arm64": struct(
        os = "linux",
        cpu = "arm64",
        npm_suffix = "linux-arm64",
    ),
    "windows_x86_64": struct(
        os = "windows",
        cpu = "x86_64",
        npm_suffix = "win32-x64",
    ),
    "windows_arm64": struct(
        os = "windows",
        cpu = "arm64",
        npm_suffix = "win32-arm64",
    ),
}

def _tsgo_tools_repo_impl(rctx):
    """Downloads the tsgo binary for a specific platform."""
    version = rctx.attr.version
    platform = rctx.attr.platform

    info = _PLATFORMS[platform]
    npm_suffix = info.npm_suffix

    url = "https://registry.npmjs.org/@typescript/native-preview-{suffix}/-/native-preview-{suffix}-{version}.tgz".format(
        suffix = npm_suffix,
        version = version,
    )

    rctx.download_and_extract(
        url = url,
        type = "tar.gz",
        stripPrefix = "package",
        integrity = rctx.attr.integrity,
    )

    # The tsgo binary is at lib/tsgo inside the npm package (or just tsgo on windows)
    is_windows = info.os == "windows"
    binary_name = "tsgo.exe" if is_windows else "tsgo"

    # Find the binary - it may be at the top level or under lib/
    rctx.file("BUILD.bazel", content = """
load("@bazel_skylib//rules:native_binary.bzl", "native_binary")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "tsgo_bin",
    srcs = glob(["**/tsgo", "**/tsgo.exe"]),
)

native_binary(
    name = "tsgo",
    src = ":tsgo_bin",
    out = "{binary_name}",
)
""".format(binary_name = binary_name))

tsgo_tools_repo = repository_rule(
    implementation = _tsgo_tools_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "platform": attr.string(mandatory = True),
        "integrity": attr.string(doc = "Subresource Integrity hash for the download."),
    },
    doc = "Downloads the tsgo compiler binary for a specific platform.",
)

def _tsgo_toolchains_repo_impl(rctx):
    """Creates a repository with toolchain declarations for all platforms."""
    version = rctx.attr.version
    tools_repo = rctx.attr.tools_repo

    # Generate toolchain targets for each platform
    toolchain_defs = []
    toolchain_targets = []

    for platform_key, info in _PLATFORMS.items():
        toolchain_name = "tsgo_toolchain_{key}".format(key = platform_key)
        impl_name = "tsgo_impl_{key}".format(key = platform_key)

        toolchain_defs.append("""
tsgo_toolchain(
    name = "{impl_name}",
    tsgo = "@{tools_repo}_{key}//:tsgo",
    version = "{version}",
)

toolchain(
    name = "{toolchain_name}",
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{cpu}",
    ],
    toolchain = ":{impl_name}",
    toolchain_type = "@rules_pnpm_tsgo//tsgo:toolchain_type",
)
""".format(
            impl_name = impl_name,
            toolchain_name = toolchain_name,
            tools_repo = tools_repo,
            key = platform_key,
            version = version,
            os = info.os,
            cpu = info.cpu,
        ))

        toolchain_targets.append('":{toolchain_name}"'.format(toolchain_name = toolchain_name))

    build_content = """
load("@rules_pnpm_tsgo//tsgo:toolchain.bzl", "tsgo_toolchain")

package(default_visibility = ["//visibility:public"])
{defs}
""".format(defs = "\n".join(toolchain_defs))

    rctx.file("BUILD.bazel", content = build_content)

tsgo_toolchains_repo = repository_rule(
    implementation = _tsgo_toolchains_repo_impl,
    attrs = {
        "version": attr.string(mandatory = True),
        "tools_repo": attr.string(
            default = "tsgo_tools",
            doc = "Name prefix for the tools repositories.",
        ),
    },
    doc = "Creates toolchain declarations for all supported tsgo platforms.",
)

def tsgo_register_toolchains(name = "tsgo", version = None, register = True, **kwargs):
    """Convenience macro to download tsgo and register toolchains.

    Args:
        name: Base name for the repositories.
        version: tsgo version to download.
        register: Whether to call native.register_toolchains().
        **kwargs: Additional arguments passed to repository rules.
    """
    if not version:
        fail("version is required")

    tools_repo = name + "_tools"

    for platform_key in _PLATFORMS:
        tsgo_tools_repo(
            name = "{tools_repo}_{key}".format(tools_repo = tools_repo, key = platform_key),
            version = version,
            platform = platform_key,
            **kwargs
        )

    tsgo_toolchains_repo(
        name = name + "_toolchains",
        version = version,
        tools_repo = tools_repo,
    )

    if register:
        native.register_toolchains("@{name}_toolchains//:all".format(name = name))
