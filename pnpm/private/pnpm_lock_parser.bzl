"""Minimal parser for pnpm-lock.yaml v9.

Only extracts the subset needed for type-checking: package names, versions,
and integrity hashes. Does NOT handle the full YAML spec -- just the regular
structure that pnpm produces.
"""

def parse_pnpm_lock(content):
    """Parse pnpm-lock.yaml to extract package metadata.

    Args:
        content: The full text content of pnpm-lock.yaml.

    Returns:
        A dict of {name_at_version: struct(name, version, integrity)}.
    """
    packages = {}
    in_packages = False
    current_pkg = None

    for line in content.split("\n"):
        stripped = line.strip()

        # Detect the packages: section
        if line == "packages:" or line == "packages:\n":
            in_packages = True
            continue

        # A non-indented, non-empty line ends the packages section
        if in_packages and stripped and not line.startswith(" "):
            in_packages = False
            current_pkg = None
            continue

        if not in_packages:
            continue

        # Package entry line: starts with exactly 2 spaces, ends with ":"
        # e.g. "  '@types/node@22.19.8':" or "  undici-types@6.21.0:"
        if line.startswith("  ") and not line.startswith("    ") and stripped.endswith(":"):
            pkg_key = stripped[:-1]  # Remove trailing ":"

            # Remove quotes if present
            if pkg_key.startswith("'") and pkg_key.endswith("'"):
                pkg_key = pkg_key[1:-1]
            elif pkg_key.startswith('"') and pkg_key.endswith('"'):
                pkg_key = pkg_key[1:-1]

            # Parse name@version
            name, version = _split_name_version(pkg_key)
            if name and version:
                current_pkg = pkg_key
                packages[current_pkg] = struct(
                    name = name,
                    version = version,
                    integrity = "",
                )

        # Resolution line with integrity hash
        elif current_pkg and "integrity:" in stripped:
            integrity = _extract_integrity(stripped)
            if integrity:
                prev = packages[current_pkg]
                packages[current_pkg] = struct(
                    name = prev.name,
                    version = prev.version,
                    integrity = integrity,
                )

    return packages

def _split_name_version(pkg_key):
    """Split '@types/node@22.19.8' into ('@types/node', '22.19.8')."""
    # For scoped packages like @types/node@1.0.0, the last @ is the version separator
    if pkg_key.startswith("@"):
        # Scoped package: find the second @
        at_idx = pkg_key.find("@", 1)
    else:
        at_idx = pkg_key.find("@")

    if at_idx == -1:
        return None, None

    return pkg_key[:at_idx], pkg_key[at_idx + 1:]

def _extract_integrity(line):
    """Extract the integrity hash from a resolution line.

    Handles formats like:
        resolution: {integrity: sha512-abc123==}
        resolution: {integrity: sha512-abc123==, tarball: ...}
    """
    key = "integrity: "
    start = line.find(key)
    if start == -1:
        return ""
    start += len(key)

    # Find the end: either "}" or "," (whichever comes first)
    end_brace = line.find("}", start)
    end_comma = line.find(",", start)

    if end_comma != -1 and (end_brace == -1 or end_comma < end_brace):
        end = end_comma
    elif end_brace != -1:
        end = end_brace
    else:
        end = len(line)

    return line[start:end].strip()

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
