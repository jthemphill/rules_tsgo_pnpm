"""Shared utilities for npm package handling."""

def npm_tarball_url(name, version):
    """Compute the npm registry tarball URL for a package.

    Args:
        name: Package name (e.g., "@types/node" or "undici-types").
        version: Package version (e.g., "22.19.8").

    Returns:
        The full tarball URL.
    """
    # For scoped packages: @scope/pkg -> @scope/pkg/-/pkg-version.tgz
    # For unscoped: pkg -> pkg/-/pkg-version.tgz
    if name.startswith("@"):
        # Scoped: @types/node -> basename is "node"
        basename = name.split("/")[-1]
        return "https://registry.npmjs.org/{name}/-/{basename}-{version}.tgz".format(
            name = name,
            basename = basename,
            version = version,
        )
    else:
        return "https://registry.npmjs.org/{name}/-/{name}-{version}.tgz".format(
            name = name,
            version = version,
        )
