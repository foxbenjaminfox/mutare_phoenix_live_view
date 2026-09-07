# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`mutare_phoenix_live_view` is a **plugin for the [Mutare](https://hex.pm/packages/mutare) mutation-testing engine**. It is not an application — it ships six `Mutare.Mutator` families that mutate the Phoenix LiveView surface (socket navigation, callback reply tuples, stream ops, pushed client events, child-component updates, lifecycle-hook attachment). A mutant that *survives* the host project's test suite marks a missing assertion.

Read `README.md` first — it documents each family, the mutation it makes, and the test gap a survivor exposes. The thesis: a LiveView callback's whole observable contract is *which* socket-transforming call ran and *what* tuple it returned, so this package turns each under-asserted transformation into a located survivor.

## Commands

```sh
mix deps.get                       # fetch deps (mutare, mutare_plug, and mutare_phoenix are local path deps)
mix compile
mix test                           # full suite (all async)
mix test test/mutare/phoenix/live_view/navigation_test.exs        # one file
mix test test/mutare/phoenix/live_view/navigation_test.exs:21     # one test by line
mix check                          # alias: `format --check-formatted` then `credo` then `dialyzer`
mix format                         # apply formatting
mix dialyzer                       # type analysis (first run builds the PLT in priv/plts/)
mix docs                           # ExDoc (dev only)
```

Run the demo target (dogfoods the package against a project with deliberate test gaps):

```sh
mix compile                        # MUST compile the root first — the demo's .mutare.exs
mix mutare examples/demo           # appends the compiled package ebins to its code path
```

## Dependencies & layout

- `{:mutare, "~> 0.1"}` (the engine) and `{:mutare_phoenix, "~> 0.1"}` (the base package, which pulls `mutare_plug` — the `Plug.Conn` families) come from Hex. All three repos are also checked out as siblings of this one; the Mutare engine source (e.g. `Mutare.Test`, `Mutare.Mutator`, `Mutare.Transform.Calls`) lives in `../mutare/lib` — read it there when you need the contract. To develop against unreleased core or base-package changes, switch the dep to `path: "../mutare"` / `path: "../mutare_phoenix"` locally and switch it back before committing.
- This package **builds on** `mutare_phoenix` the way `phoenix_live_view` builds on `phoenix`: depending on it puts the controller-level (`Mutare.Phoenix.all/0`) and, through `mutare_plug`, the conn-level (`Mutare.Plug.all/0`) families on the code path, but `Mutare.Phoenix.LiveView.all/0` returns **only the six LiveView families** — compose the other two presets explicitly for the full surface, and list `Mutare.Phoenix` under `:extensions` for its defensive Phoenix macro routing.
- `lib/mutare/phoenix/live_view.ex` is the public entry (`all/0`); each family is one module under `lib/mutare/phoenix/live_view/`.
- The package matches module **names** (`[:Phoenix, :LiveView]`), so it depends on neither `phoenix` nor `phoenix_live_view`; resolution happens in the consumer's project.

## The mutator contract

Each family is `@behaviour Mutare.Mutator`. Key callbacks and how they're used here:

- `name/0` — the family's recorded atom (`:lv_nav`, `:lv_reply`, `:lv_stream`, `:lv_event`, `:lv_send_update`, `:lv_hook`).
- `mutate/1` (node-local) vs `mutate/2` (with context). **Most families return `:skip` from `mutate/1`** and do their real work in `mutate/2`, because the decision needs `context.pipe_mode` to recover *effective arity*: a piped `s |> push_navigate(to: p)` writes one arg but is arity 2.
- `return_replacements/2` (structural hook) — `Reply` uses this instead of call resolution. It is gated on the enclosing module's `context.behaviours` (must implement `Phoenix.LiveView` or `Phoenix.LiveComponent`).
- `macro_routes/0` — lives on the separate `Mutare.MacroRouting` behaviour, which a mutator may also implement (listing it under `:mutators` auto-registers its routes). `Navigation` declares it defensively: the LiveView compile-time DSL — `live`/`live_session` (`Phoenix.LiveView.Router`), `on_mount`, and `Phoenix.Component`'s `attr`/`slot`/`embed_templates` — is registered `:skip`, because those declarations run once as mutant 0 under Mutare's compile-once model, so mutations inside them can never activate (they'd be uninformative survivors). LiveView *callback* bodies are ordinary runtime code and are still mutated.
- `variants/0` + `Mutare.Mutator.Mutation.tagged/2` — the families that produce more than one *kind* tag each mutation at production (`Stream`: `swap`/`at`/`limit`; `SendUpdate`: `remove`/`immediate`; `Hook`: `attach`/`detach`), so a qualified `# mutare:ignore[lv_stream:at]` suppresses one kind. Labels are public API; the family's moduledoc documents its vocabulary.
- `argument_marks/1` — two families pin argument positions against core's value families: `SendUpdate` marks `send_update_after`'s delay with the shared `:timeout` label (core `IntegerLiteral`/`AtomLiteral` react — the `immediate` kind owns the timing question wholesale), and `Hook` marks the hook name/stage with `Mutare.Mutator.structural_label()` (every `:skip_arguments`-honouring value family declines there).

Engine helpers the families call (from `../mutare`):
- `Mutare.Transform.Calls.resolved_call(node)` → `{module_path, fun, args, rebuild}`, resolving direct / aliased / bare-imported (`use`-injected) calls to a canonical module path. `rebuild.(fun, args)` reconstructs the call in its original written form.
- `Mutare.Mutator.effective_arity(args, pipe_mode)` — arity accounting for an implicit piped argument.
- `Mutare.AST.literal/1`, `Mutare.AST.key_atom/1` — Sourceror node builders.

**To add a family:** implement the `Mutare.Mutator` behaviour in a new module under `lib/mutare/phoenix/live_view/`; add it to the literal list in `all/0` (`lib/mutare/phoenix/live_view.ex` — there is no `@families` attribute) **and** update that function's doctest, which asserts the exact list; if it mutates a call this package doesn't already touch, export that function/arity from `test/support/live_view_stubs.ex` (import resolution reflects on real arities); and add a mirroring test file under `test/mutare/phoenix/live_view/`.

## Design invariants (respect these when editing or adding a family)

- **Mutants must be valid alternatives, not crashes.** The whole point (see README "Why not the built-in atom mutators?") is that a swap produces a value a LiveView could legitimately return, so a survivor means a real missing assertion rather than an uninformative crash-kill. Removal families collapse a call to its *faithful happy-path return*: `:lv_event` → the socket (or `Function.identity()` when piped); `:lv_send_update` → `:ok` for `send_update`, a fresh `:erlang.make_ref()` for `send_update_after`.
- **Arity guards keep every metamutant compiling.** All mutants for a source are embedded in one shared build; one uncompilable mutant sinks it. So a swap fires only at the arity both functions share (`push_navigate`/`push_patch` → arity 2; `stream_insert`/`stream_delete` → arity 3, leaving `stream_insert/4` alone). `assert_metamutant_compiles/2` is the test that pins this.
- The `:Elixir`-led / `:erlang`-qualified no-op nodes (`Function.identity()`, `:erlang.make_ref()`) are written that way deliberately — alias resolution never rewrites them, so the no-op always names the real function.
- **Clean-meta rule.** To change a value *in place*, keep the original node's Sourceror metadata so it re-renders inline; build genuinely new nodes (e.g. a swapped keyword key or reply tag) with *fresh* meta, never carrying a stale token. Carrying stale line metadata makes Sourceror expand the call across lines.
- **Dedup with built-ins takes three forms — know which applies before adding a mutation.** (1) *Behaviour gate*: `:lv_reply`'s reshape can look like the built-in GenServer reply mutator, but the two never double-fire because `:lv_reply` is gated on the enclosing module's `Phoenix.LiveView` / `Phoenix.LiveComponent` behaviours (the GenServer one gates on its own); the `reply_test.exs` "not duplicated by the built-in" block pins this — preserve the gate if you touch `Reply`. (2) *Overlap covering*: `:lv_stream`'s `at: 0 ↔ at: -1` swap substitutes exactly the value node, so core's `Mutare.Transform.Overlap` recognises the rewrite as covering and prunes `IntegerLiteral`'s redundant leaves there — build any similar option-value swap as the original call with exactly ONE node replaced (fresh literal via `Mutare.AST.literal/1`, everything else reused verbatim), and pin the pruning with a test. (3) *Ownership abstention*: a mutation core already owns is not re-emitted at all — no `reset:`/`update_only:` drop in `:lv_stream`, because dropping a boolean-defaulting-false entry is core `BooleanLiteral`'s `true → false` flip in disguise.
- Sites are silenced in consumer code with `# mutare:ignore[<family>]` (e.g. `# mutare:ignore[lv_nav]`).

## Tests

- `import Mutare.Test` (from `../mutare`) gives the harness. Use the right path for the assertion:
  - `node_mutations(snippet, Mutator, pipe_mode \\ :unpiped)` — pure-AST node path; only *qualified* calls resolve, no transform pre-pass. Tightest unit of `mutate/1`·`mutate/2`.
  - `diffs_for(source, [Mutators], :family_name)` — drives the **real** `Mutare.transform_string/2` (alias/import/pipe resolution + equivalent-sibling suppression), isolating one family's `{original, mutated}` pairs. This is the main assertion style.
  - `assert_metamutant_compiles(source, [Mutators])` — the compile safety net; `source` must be a complete `defmodule`.
- `test/support/live_view_stubs.ex` defines minimal stand-in `Phoenix.LiveView` / `Phoenix.LiveComponent` modules, loaded **only in `:test`** via `elixirc_paths(:test)`. They exist so the suite can (a) resolve bare-imported calls — `Mutare.Transform.Imports` reflects on real exported arities, so the stubs must export `push_navigate/2`, `stream_insert/3` **and** `/4`, etc.; and (b) surface a `use`-injected `@behaviour` for the `:lv_reply` gate. If you add a mutated function/arity, add it to these stubs. Empty `Phoenix.LiveView.Router` / `Phoenix.Component` stand-ins are the module-key targets for `Navigation.macro_routes/0` — purely syntactic, no DSL macros needed.
- One test file per family, plus `live_view_test.exs` for `all/0`.

## Scope boundaries

- The auth-hook `:cont`/`:halt` decision (in `on_mount/4` and *inside* hook functions) is **not** here — Mutare's built-in `:convention` family covers it. `:lv_hook` owns a different axis: removing the `attach_hook/4`/`detach_hook/3` call itself.
- The socket-level `Phoenix.LiveView.redirect/2` `to:`/`external:` kind is **not** mutated by this package — it has no LiveView-specific contract beyond the open-redirect property the conn-level base families already model.
