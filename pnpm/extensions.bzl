"""Bzlmod extension for pnpm npm package fetching."""

load("//pnpm/private:npm_types_repo.bzl", "npm_types")

def _pnpm_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for lock in mod.tags.lock:
            npm_types(
                name = lock.name,
                pnpm_lock = lock.pnpm_lock,
            )

pnpm = module_extension(
    implementation = _pnpm_extension_impl,
    tag_classes = {
        "lock": tag_class(attrs = {
            "name": attr.string(default = "npm"),
            "pnpm_lock": attr.label(mandatory = True),
        }),
    },
)
