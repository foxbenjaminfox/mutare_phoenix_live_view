# Mutare Phoenix LiveView

Custom [Mutare](https://hex.pm/packages/mutare) mutators for the **Phoenix LiveView surface** —
the socket navigation, callback reply tuples, stream operations, pushed client events, and
child-component updates a LiveView performs.

A LiveView callback's whole observable contract is **which socket-transforming call ran and
what tuple it returned** — the navigation kind, the reply it sent, the stream op it performed.
These are exactly the things a suite tends to under-assert: a test that checks "something
happened" but not *which* transformation leaves a gap. `mutare_phoenix_live_view` turns each
such gap into a located [Mutare](https://hex.pm/packages/mutare) survivor.

It **builds on** [`mutare_phoenix`](https://hex.pm/packages/mutare_phoenix) (the conn-level base
families) the way `phoenix_live_view` builds on `phoenix`: it depends on it, so those families
are on your code path too, ready to compose.

## The six families

`Mutare.Phoenix.LiveView.all/0` returns six mutator families:

| Family | Name | Mutation | The gap a survivor exposes |
| --- | --- | --- | --- |
| `Mutare.Phoenix.LiveView.Navigation` | `:lv_nav` | swaps `push_navigate` ↔ `push_patch` | no test pins *how* navigation happened (remount vs in-process patch) — `assert_redirect` vs `assert_patch` |
| `Mutare.Phoenix.LiveView.Reply` | `:lv_reply` | drops a callback's optional trailing tuple element (`{:reply, payload, socket}` → `{:noreply, socket}`, `{:ok, socket, opts}` → `{:ok, socket}`) | no test checks the JS-hook reply payload or the `mount` option. Fires in `@behaviour Phoenix.LiveView` / `Phoenix.LiveComponent` modules |
| `Mutare.Phoenix.LiveView.Stream` | `:lv_stream` | swaps `stream_insert` ↔ `stream_delete` (`swap`); swaps `at: 0 ↔ at: -1` on `stream_insert/4` (`at` — prepend vs append); drops the `limit:` entry of `stream/4` / `stream_insert/4` (`limit` — the unbounded stream) | no test asserts the stream's *contents*, the inserted item's *position*, or what falls off past the limit |
| `Mutare.Phoenix.LiveView.Event` | `:lv_event` | removes `push_event/3,4` | no test asserts the event reaches the client — `assert_push_event` |
| `Mutare.Phoenix.LiveView.SendUpdate` | `:lv_send_update` | removes `send_update/2,3` / `send_update_after/3,4` (`remove` — collapses to a faithful stand-in: `:ok`, or a fresh `make_ref()`); turns `send_update_after/3,4` into an *immediate* `send_update` that still yields a ref (`immediate` — the delay deleted) | no test asserts the child update happens — or that it is *deferred* |
| `Mutare.Phoenix.LiveView.Hook` | `:lv_hook` | removes `attach_hook/4` (`attach` — the hook never runs) and `detach_hook/3` (`detach` — the hook keeps running), collapsing to the socket | no test depends on the lifecycle hook's attachment or detachment |

Each family matches its call written directly (`Phoenix.LiveView.push_navigate(...)`), aliased,
or bare-imported (`push_navigate(...)`, the form `use MyAppWeb, :live_view` produces). Silence a
site with `# mutare:ignore[lv_nav]` (and likewise per family); the multi-kind families declare
variant labels — the ones in parentheses above — so `# mutare:ignore[lv_stream:limit]` or
`# mutare:ignore[lv_send_update:immediate]` suppresses one kind without silencing the rest.

Two positions are additionally *pinned* against Mutare's built-in value families:
`send_update_after`'s delay (the `immediate` mutant owns the timing question, so core's
near-unkillable `1000 → 1001` mutants are skipped there) and a hook's name/stage atoms (a
renamed hook is near-equivalent; a mutated stage just crashes).

The auth-hook `:cont`/`:halt` decision (`on_mount`/`attach_hook`) is **not** in this package —
it is covered by Mutare's built-in `:convention` family (on by default), which flips the atom
literal wherever it appears. The marquee LiveView auth-bypass coverage comes for free.

## Usage

`mutare_phoenix_live_view` rides on the [Mutare](https://hex.pm/packages/mutare) engine and
builds on `mutare_phoenix`, so add them as `:dev`/`:test` dependencies:

```elixir
# mix.exs
defp deps do
  [
    {:mutare, "~> 0.1", only: [:dev, :test], runtime: false},
    {:mutare_phoenix, "~> 0.1", only: [:dev, :test], runtime: false},
    {:mutare_phoenix_live_view, "~> 0.1", only: [:dev, :test], runtime: false}
  ]
end
```

Then list the families in `.mutare.exs`. Setting `:mutators` **replaces** Mutare's default set,
so include the `:builtins` group token to keep the built-ins on (it includes `:convention`):

```elixir
# .mutare.exs — a LiveView app
[mutators: [:builtins] ++ Mutare.Phoenix.LiveView.all()]
```

A full-stack app that also wants the conn-level base families composes all three groups:

```elixir
# .mutare.exs — a full-stack Phoenix + LiveView app
[mutators: [:builtins] ++ Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()]
```

`all/0` returns only the five LiveView families — it does **not** include the base
`mutare_phoenix` families, so compose `Mutare.Phoenix.all/0` explicitly when you want the full
Phoenix + LiveView surface. Run it the usual way:

```
mix mutare
```

## Why not the built-in atom mutators?

In a reply-tag or status position, Mutare's built-in atom swaps (`:ok → :error` / `:mutare`)
produce a value that **crashes** — an uninformative kill that tells you nothing about test
quality. These families swap to a *valid* alternative (a real navigation/stream/reply a
LiveView could legitimately return), so a survivor means a genuine missing assertion rather than
a crash.

The one exception is `push_navigate → push_patch`: `push_patch` is only valid to the *same*
LiveView, so against a route backed by a different LiveView the mutant raises at runtime and the
kill is the uninformative kind. The swap still earns its keep in the common same-LiveView case,
and the `push_patch → push_navigate` direction is always a valid alternative.

## Example

[`examples/demo`](https://github.com/foxbenjaminfox/mutare_phoenix_live_view/tree/master/examples/demo) is a standalone mini-project — a LiveView, a LiveView auth
hook, and a controller over tiny `Phoenix.LiveView` / `Plug.Conn` / `Phoenix.Controller`
stand-ins — with deliberate test gaps, one or more survivors per family. From the repo root
(compile the packages once so the mutators are on the code path):

```
mix compile
mix mutare examples/demo
```

## Scope

The conn-level base families live in the companion
[`mutare_phoenix`](https://hex.pm/packages/mutare_phoenix); the mutation engine is
[`mutare`](https://hex.pm/packages/mutare). Compose `Mutare.Phoenix.all/0` alongside
`Mutare.Phoenix.LiveView.all/0` (see "Usage") for the full conn + socket surface.

## License

MIT — see [LICENSE](LICENSE).
