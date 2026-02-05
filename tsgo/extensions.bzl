"""Bzlmod extension for the tsgo toolchain."""

load("//tsgo:repositories.bzl", "tsgo_register_toolchains")

def _tsgo_extension_impl(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name in registrations:
                if toolchain.version != registrations[toolchain.name]:
                    fail("Multiple conflicting tsgo toolchain versions for '{name}': {v1} vs {v2}".format(
                        name = toolchain.name,
                        v1 = registrations[toolchain.name],
                        v2 = toolchain.version,
                    ))
            else:
                registrations[toolchain.name] = toolchain.version

    for name, version in registrations.items():
        tsgo_register_toolchains(
            name = name,
            version = version,
            register = False,  # Registration happens via MODULE.bazel
        )

tsgo = module_extension(
    implementation = _tsgo_extension_impl,
    tag_classes = {
        "toolchain": tag_class(attrs = {
            "name": attr.string(default = "tsgo"),
            "version": attr.string(mandatory = True),
        }),
    },
)
