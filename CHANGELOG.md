# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - Unreleased

Initial release.

### Added

- `Mutare.Phoenix.LiveView.Navigation` (`:lv_nav`) — swaps `push_navigate` ↔
  `push_patch` at the arity-2 form both share.
- `Mutare.Phoenix.LiveView.Reply` (`:lv_reply`) — drops a callback's optional
  trailing tuple element (`{:reply, payload, socket}` → `{:noreply, socket}`,
  `{:ok, socket, opts}` → `{:ok, socket}`), gated on the enclosing module's
  `Phoenix.LiveView` / `Phoenix.LiveComponent` behaviour.
- `Mutare.Phoenix.LiveView.Stream` (`:lv_stream`) — swaps `stream_insert` ↔
  `stream_delete` at the arity-3 form both share.
- `Mutare.Phoenix.LiveView.Event` (`:lv_event`) — removes `push_event/3,4`,
  collapsing to the socket (or `Function.identity()` when piped).
- `Mutare.Phoenix.LiveView.SendUpdate` (`:lv_send_update`) — removes
  `send_update/2,3` / `send_update_after/3,4`, collapsing to a faithful
  stand-in (`:ok` / a fresh `make_ref()` for `_after`'s timer ref).
- Registers the LiveView compile-time DSL (`live`/`live_session`, `on_mount`,
  `attr`/`slot`/`embed_templates`) as `:skip` through `Mutare.MacroRouting`,
  so declarations that run once as mutant 0 are left unmutated.
- `Mutare.Phoenix.LiveView.all/0` for splicing the five families into a
  `:mutators` list, composing with `Mutare.Phoenix.all/0`.
