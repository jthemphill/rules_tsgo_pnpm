"""Public API for tsgo Bazel rules.

This module provides ts_project, a drop-in replacement for rules_ts ts_project
that uses tsgo (the Go-based TypeScript compiler) instead of tsc.
"""

load("//tsgo/private:providers.bzl", _TsInfo = "TsInfo")
load("//tsgo/private:ts_config.bzl", _ts_config = "ts_config")
load("//tsgo/private:ts_types.bzl", _ts_types = "ts_types")
load("//tsgo/private:tsgo_compile.bzl", "ts_project_impl")

TsInfo = _TsInfo
ts_config = _ts_config
ts_types = _ts_types

_ts_project_rule = rule(
    implementation = ts_project_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".ts", ".tsx", ".mts", ".cts"],
            doc = "TypeScript source files to compile.",
        ),
        "deps": attr.label_list(
            doc = "Targets that produce .d.ts declarations needed by this compilation.",
        ),
        "tsconfig": attr.label(
            allow_single_file = [".json"],
            doc = "A tsconfig.json file or ts_config target to extend. " +
                  "When provided, the generated tsconfig will extend this file, " +
                  "inheriting its compilerOptions. Bazel-specific options " +
                  "(rootDirs, outDir, rootDir, files) are always overridden.",
        ),
        "declaration": attr.bool(
            default = True,
            doc = "Whether to emit .d.ts declaration files.",
        ),
        "declaration_map": attr.bool(
            default = False,
            doc = "Whether to emit .d.ts.map declaration map files.",
        ),
        "source_map": attr.bool(
            default = False,
            doc = "Whether to emit .js.map source map files.",
        ),
        "emit": attr.bool(
            default = True,
            doc = "Whether to emit .js output files. Set to False for type-check only.",
        ),
        "root_dir": attr.string(
            doc = "Root directory for input files. Defaults to auto-computed common " +
                  "prefix of all source files.",
        ),
        "out_dir": attr.string(
            doc = "Override the output directory for compiled files.",
        ),
        "args": attr.string_list(
            doc = "Additional arguments passed to tsgo.",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Runtime data files needed by the compiled outputs.",
        ),
    },
    toolchains = ["//tsgo:toolchain_type"],
    doc = "Compiles TypeScript source files using tsgo.",
)

def ts_project(
        name,
        srcs = None,
        deps = [],
        tsconfig = None,
        declaration = True,
        declaration_map = False,
        source_map = False,
        emit = True,
        root_dir = None,
        out_dir = None,
        args = [],
        **kwargs):
    """Compiles TypeScript using tsgo.

    Drop-in replacement for rules_ts ts_project. Uses the tsgo Go-based
    TypeScript compiler instead of tsc, following rules_rust patterns
    (direct binary invocation, no file copying, explicit dependency paths).

    Args:
        name: Target name.
        srcs: TypeScript source files. Defaults to glob(["**/*.ts", "**/*.tsx"]).
        deps: Targets producing .d.ts declarations this target depends on.
        tsconfig: A tsconfig.json file or ts_config target to extend.
        declaration: Emit .d.ts declaration files.
        declaration_map: Emit .d.ts.map files.
        source_map: Emit .js.map files.
        emit: Emit .js files. Set to False for type-check only.
        root_dir: Root directory for input files.
        out_dir: Override the output directory.
        args: Additional tsgo arguments.
        **kwargs: Additional arguments to the underlying rule.
    """
    if srcs == None:
        srcs = native.glob(
            ["**/*.ts", "**/*.tsx"],
            exclude = ["**/*.d.ts", "**/*_test.ts", "**/*_test.tsx"],
        )

    _ts_project_rule(
        name = name,
        srcs = srcs,
        deps = deps,
        tsconfig = tsconfig,
        declaration = declaration,
        declaration_map = declaration_map,
        source_map = source_map,
        emit = emit,
        root_dir = root_dir,
        out_dir = out_dir,
        args = args,
        **kwargs
    )
