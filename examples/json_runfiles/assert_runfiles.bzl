"""Asserts that a dep exposes a file in its default runfiles."""

def _assert_runfiles_impl(ctx):
    filename = ctx.attr.filename
    runfiles_files = ctx.attr.dep[DefaultInfo].default_runfiles.files.to_list()

    found = False
    for f in runfiles_files:
        if f.basename == filename:
            found = True
            break

    if not found:
        fail("expected '{}' in DefaultInfo.default_runfiles of {}".format(filename, ctx.attr.dep.label))

    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(out, "ok\n")
    return [DefaultInfo(files = depset([out]))]

assert_runfiles = rule(
    implementation = _assert_runfiles_impl,
    attrs = {
        "dep": attr.label(mandatory = True),
        "filename": attr.string(mandatory = True),
    },
)
