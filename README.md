# rules_tsgo

Bazel rules for TypeScript using [tsgo](https://github.com/microsoft/typescript-go) (the Go-based TypeScript 7 compiler).

Supports npm type dependencies from **pnpm** (`pnpm-lock.yaml`) and **bun** (`bun.lock`) lockfiles.

Designed as a drop-in replacement for [rules_ts](https://github.com/aspect-build/rules_ts), following architectural patterns from [rules_rust](https://github.com/bazelbuild/rules_rust).

## Setup

Add to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_tsgo", version = "0.0.1")

tsgo = use_extension("@rules_tsgo//tsgo:extensions.bzl", "tsgo")
tsgo.toolchain(version = "7.0.0-dev.20260204.1")
use_repo(tsgo, "tsgo_toolchains")

register_toolchains("@tsgo_toolchains//:all")
```

### npm types from pnpm

```starlark
npm = use_extension("@rules_tsgo//npm:extensions.bzl", "npm")
npm.lock(lockfile = "//:pnpm-lock.yaml")
use_repo(npm, "npm")
```

### npm types from bun

```starlark
npm = use_extension("@rules_tsgo//npm:extensions.bzl", "npm")
npm.lock(lockfile = "//:bun.lock")
use_repo(npm, "npm")
```

Then depend on types in your `BUILD.bazel`:

```starlark
ts_project(
    name = "server",
    srcs = ["server.ts"],
    deps = ["@npm//:@types/node"],
)
```

## Rules

### `ts_project`

Compiles TypeScript source files using tsgo.

```starlark
load("@rules_tsgo//tsgo:defs.bzl", "ts_project")

ts_project(
    name = "my_lib",
    srcs = ["index.ts", "util.ts"],
    deps = ["//other/package"],
)
```

| Attribute | Default | Description |
|-----------|---------|-------------|
| `srcs` | `glob(["**/*.ts", "**/*.tsx"])` | TypeScript source files |
| `deps` | `[]` | Targets producing `.d.ts` declarations |
| `declaration` | `True` | Emit `.d.ts` files |
| `declaration_map` | `False` | Emit `.d.ts.map` files |
| `source_map` | `False` | Emit `.js.map` files |
| `emit` | `True` | Emit `.js` files (set `False` for type-check only) |
| `args` | `[]` | Additional tsgo CLI flags |

### `ts_types`

Wraps existing `.d.ts` files so they can be used as `deps` of `ts_project`.

```starlark
load("@rules_tsgo//tsgo:defs.bzl", "ts_types")

ts_types(
    name = "shared_types",
    srcs = ["shared.d.ts"],
)
```

## How it works

Building will generate a `tsconfig.json` in the build sandbox that looks like this:

```json
{
  "compilerOptions": {
    "rootDirs": [".", "bazel-out/darwin_arm64-fastbuild/bin"],
    "outDir": "bazel-out/darwin_arm64-fastbuild/bin/my/package"
  },
  "files": ["my/package/index.ts"]
}
```

`rootDirs` tells TypeScript to treat the source tree and the output tree as a single virtual filesystem. When `my/package/index.ts` imports `../other/util`, TypeScript finds `util.d.ts` in `bazel-out/.../other/` — no file copying needed.

## Examples

- [`examples/basic`](examples/basic) — single-package compilation
- [`examples/monorepo`](examples/monorepo) — multi-package with `ts_types` → `ts_project` → `ts_project` dependency chain
- [`examples/with_types`](examples/with_types) — npm `@types/node` via pnpm lockfile
- [`examples/with_bun`](examples/with_bun) — npm `@types/node` via bun lockfile

```
bazel build //examples/...
```

## Status

Working:
- Toolchain download for 6 platforms (macOS/Linux/Windows x x64/arm64)
- Single and multi-package compilation with `.d.ts` dependency flow
- Type checking (tsgo exits non-zero on type errors, failing the build)
- npm `@types/*` package fetching from pnpm and bun lockfiles

Not yet implemented:
- Transpiler split (SWC/esbuild for JS emit, tsgo for type-checking)
