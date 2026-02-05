"""Parser for bun.lock (JSONC format).

bun.lock is JSON with comments and trailing commas. The packages section maps
package names to arrays:
  "pkg-name": ["pkg-name@version", "", { ... }, "sha512-..."]

Index 0: name@version string
Index 1: registry path (empty for npm registry)
Index 2: metadata object (dependencies, etc.)
Index 3: integrity hash
"""

def parse_bun_lock(content):
    """Parse bun.lock to extract package metadata.

    Args:
        content: The full text content of bun.lock (JSONC).

    Returns:
        A dict of {name_at_version: struct(name, version, integrity)}.
    """
    clean = _strip_jsonc(content)
    data = json.decode(clean)

    packages = {}
    pkg_entries = data.get("packages", {})
    for _pkg_name, entry in pkg_entries.items():
        if type(entry) != "list" or len(entry) < 1:
            continue

        name_at_version = entry[0]
        integrity = entry[3] if len(entry) > 3 else ""

        name, version = _split_name_version(name_at_version)
        if name and version:
            packages[name_at_version] = struct(
                name = name,
                version = version,
                integrity = integrity,
            )

    return packages

def _split_name_version(name_at_version):
    """Split 'pkg@version' or '@scope/pkg@version' into (name, version)."""
    if name_at_version.startswith("@"):
        at_idx = name_at_version.find("@", 1)
    else:
        at_idx = name_at_version.find("@")

    if at_idx == -1:
        return None, None

    return name_at_version[:at_idx], name_at_version[at_idx + 1:]

def _strip_jsonc(content):
    """Strip // comments and trailing commas from JSONC to produce valid JSON.

    Two-pass approach that works within Starlark's for-loop-only constraint:
    1. Strip // line comments (respecting strings)
    2. Remove trailing commas before } or ]
    """

    # Pass 1: strip // comments (line-by-line, respecting strings)
    lines = content.split("\n")
    cleaned_lines = []
    for line in lines:
        cleaned_lines.append(_strip_line_comment(line))
    no_comments = "\n".join(cleaned_lines)

    # Pass 2: remove trailing commas before } or ]
    # Find positions of all commas that are followed only by whitespace then } or ]
    # Build a set of indices to skip
    skip = {}
    chars = no_comments.elems()
    length = len(chars)
    in_string = False
    for i in range(length):
        c = chars[i]
        if c == '"' and not _is_escaped(no_comments, i):
            in_string = not in_string
            continue
        if in_string:
            continue
        if c == ",":
            # Look ahead past whitespace for } or ]
            is_trailing = False
            for j in range(i + 1, length):
                cj = chars[j]
                if cj in (" ", "\t", "\n", "\r"):
                    continue
                if cj == "}" or cj == "]":
                    is_trailing = True
                break
            if is_trailing:
                skip[i] = True

    # Build result without skipped commas
    result = []
    for i in range(length):
        if i not in skip:
            result.append(chars[i])

    return "".join(result)

def _strip_line_comment(line):
    """Remove a // comment from a line, respecting string literals."""
    in_string = False
    chars = line.elems()
    for i in range(len(chars)):
        c = chars[i]
        if c == '"' and not _is_escaped(line, i):
            in_string = not in_string
            continue
        if not in_string and c == "/" and i + 1 < len(chars) and chars[i + 1] == "/":
            return line[:i]
    return line

def _is_escaped(content, pos):
    """Check if the character at pos is escaped by counting preceding backslashes."""
    count = 0
    p = pos - 1
    for _ in range(pos):
        if p < 0:
            break
        if content.elems()[p] != "\\":
            break
        count += 1
        p -= 1
    return count % 2 == 1
