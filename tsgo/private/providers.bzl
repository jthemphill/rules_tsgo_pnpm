"""Providers for TypeScript compilation with tsgo."""

TsInfo = provider(
    doc = "Information about TypeScript compilation outputs.",
    fields = {
        "declarations": "depset of .d.ts files produced by this target",
        "transitive_declarations": "depset of all .d.ts files from this target and its deps",
        "js_outputs": "depset of .js files (if emit is enabled)",
        "source_maps": "depset of .js.map files",
        "declaration_maps": "depset of .d.ts.map files",
        "srcs": "depset of source .ts files for this target",
        "type_roots": "list of paths to include as typeRoots in tsconfig (for @types packages)",
    },
)
