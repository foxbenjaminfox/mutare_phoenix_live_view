# Mutare configuration for the demo.
#
# In a real project, `mutare_phoenix_live_view` is a dependency, so its mutators (and the
# base `mutare_phoenix` ones it depends on) are already on the code path and the lines below
# are unnecessary. Here the demo lives *inside* the `mutare_phoenix_live_view` repo, where the
# packages are the root project and its dep — which the `mutare` task does not add to the
# demo's code path — so we append the compiled package `ebin`s ourselves (run `mix compile`
# in the repo root first).
for pkg <- ["mutare_phoenix", "mutare_phoenix_live_view"],
    ebin <- Path.wildcard(Path.expand("_build/*/lib/#{pkg}/ebin")),
    do: Code.append_path(String.to_charlist(ebin))

# Scope mutation to `lib/demo` (the app code), leaving the tiny stand-ins at
# `lib/web_surface.ex` unmutated. Enable this package's LiveView families (`all/0`) and the
# base `mutare_phoenix` families it composes with, plus the built-in `:convention`, so the
# auth hook's `:cont`/`:halt` decision is mutated too — demonstrating that the marquee
# LiveView auth-bypass coverage comes for free from a Mutare built-in, not from this package.
# A real full-stack app would write:
#
#     [mutators: [:builtins] ++ Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()]
#
# (`:builtins` already includes `:convention`). Here we list `:convention` explicitly — rather
# than the whole `:builtins` group — alongside the package families, so the demo output stays
# focused on the families on show.
[
  paths: ["lib/demo"],
  mutators: [:convention] ++ Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()
]
