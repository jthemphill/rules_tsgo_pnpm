"""Bzlmod extension for npm package fetching from bun.lock files.

For pnpm-lock.yaml, use aspect_rules_js's npm extension instead:
  js_npm = use_extension("@aspect_rules_js//npm:extensions.bzl", "npm")
"""

load("//npm/private:npm_types_repo.bzl", "npm_types")

def _npm_extension_impl(module_ctx):
    for mod in module_ctx.modules:
        for lock in mod.tags.lock:
            npm_types(
                name = lock.name,
                lockfile = lock.lockfile,
            )

npm = module_extension(
    implementation = _npm_extension_impl,
    tag_classes = {
        "lock": tag_class(attrs = {
            "name": attr.string(default = "npm"),
            "lockfile": attr.label(mandatory = True),
        }),
    },
)
