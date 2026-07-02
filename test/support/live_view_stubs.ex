# A minimal stand-in for the slice of `Phoenix.LiveView` the tests touch, loaded only in the
# test environment. `mutare_phoenix_live_view` depends on neither `phoenix_live_view` nor
# `phoenix` (it matches on module *names*), so this tiny module lets the test suite:
#
#   * resolve a **bare imported** call (`import Phoenix.LiveView; push_navigate(s, to: p)`) —
#     the form `use Phoenix.LiveView` produces — which `Mutare.Transform.Imports` resolves by
#     reflecting on the imported module's exported arities, so the functions must exist with
#     the right arity (`push_navigate/2`, `stream_insert/3` *and* `/4`, `stream_delete/3`, …);
#   * surface a `use`-injected `@behaviour Phoenix.LiveView` (for the `:lv_reply` gate) — the
#     `__using__` injects it the way the real `Phoenix.LiveView` does, so `Mutare.Transform.Uses`
#     can harvest it in-process;
#   * compile a generated metamutant without "undefined function" warnings.
#
# The callbacks are `@optional_callbacks` so a module that `use`s this (or declares the
# behaviour directly) needs implement none of them — the suite only cares about the stamped
# behaviour set, not a live LiveView.
defmodule Phoenix.LiveView do
  @moduledoc false

  @callback mount(params :: map(), session :: map(), socket :: term()) :: term()
  @callback handle_event(event :: binary(), params :: map(), socket :: term()) :: term()
  @callback handle_call(msg :: term(), from :: term(), socket :: term()) :: term()
  @callback handle_params(params :: map(), uri :: binary(), socket :: term()) :: term()

  @optional_callbacks mount: 3, handle_event: 3, handle_call: 3, handle_params: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour Phoenix.LiveView
      import Phoenix.LiveView
    end
  end

  # Socket-navigation surface (`:lv_nav`). All `(socket, opts)` — arity 2.
  def push_navigate(socket, _opts), do: socket
  def push_patch(socket, _opts), do: socket
  def redirect(socket, _opts), do: socket

  # Client-event surface (`:lv_event`). `push_event/3` is the only arity.
  def push_event(socket, _event, _payload), do: socket

  # Stream surface (`:lv_stream`). `stream_insert` has the optional `opts` arg (arity 3 *and*
  # 4); `stream_delete` is arity 3 only — the asymmetry `:lv_stream`'s arity gate guards.
  def stream_insert(socket, _name, _item), do: socket
  def stream_insert(socket, _name, _item, _opts), do: socket
  def stream_delete(socket, _name, _item), do: socket

  # Component-update surface (`:lv_send_update`). `send_update/2,3` (`(module, assigns)` /
  # `(pid, module, assigns)`) and `send_update_after/3,4` (the same two plus the delay) — every
  # arity exported so a bare-imported call resolves against the real one. Both return `:ok`
  # (`send_update_after` really returns a reference, but the suite only needs the arities).
  def send_update(_module, _assigns), do: :ok
  def send_update(_pid, _module, _assigns), do: :ok
  def send_update_after(_module, _assigns, _time), do: :ok
  def send_update_after(_pid, _module, _assigns, _time), do: :ok
end

# A matching stand-in for `Phoenix.LiveComponent`, the second behaviour `:lv_reply` gates on.
# A component's `handle_event/3` returns the same `{:reply, payload, socket}` shape a LiveView's
# does, so the reply-drop reshape applies to components too. `use`-injects the behaviour the way
# the real macro does, and imports `Phoenix.LiveView` (components share its socket helpers) so a
# bare-imported `push_event` / `stream_insert` resolves inside one.
defmodule Phoenix.LiveComponent do
  @moduledoc false

  @callback update(assigns :: map(), socket :: term()) :: term()
  @callback handle_event(event :: binary(), params :: map(), socket :: term()) :: term()

  @optional_callbacks update: 2, handle_event: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour Phoenix.LiveComponent
      import Phoenix.LiveView
    end
  end
end

# Module-key targets for `:lv_nav`'s `macro_routes/0` `:skip` registration (the `live`/
# `live_session` route DSL and the `attr`/`slot`/`embed_templates` declarative assigns). The
# registration is purely syntactic, so no DSL macros are required here — the modules only need
# to exist. (`on_mount`'s target is the `Phoenix.LiveView` stand-in above.)
defmodule Phoenix.LiveView.Router do
  @moduledoc false
end

defmodule Phoenix.Component do
  @moduledoc false
end
