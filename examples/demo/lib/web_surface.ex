# Minimal stand-ins for the slices of `Phoenix.LiveView` / `Plug.Conn` / `Phoenix.Controller`
# the demo uses, so the project runs with no real Phoenix dependency. The custom mutators
# match calls and behaviours by module *name* (`Phoenix.LiveView`, `Plug.Conn`,
# `Phoenix.Controller`), so the mutations against these stand-ins are identical to what they
# would be against the real modules. This file lives outside `lib/demo`, so `.mutare.exs`'s
# `paths: ["lib/demo"]` leaves it unmutated.

defmodule Phoenix.LiveView do
  @moduledoc """
  Tiny stand-in for the slice of `Phoenix.LiveView` the demo uses.

  `use Phoenix.LiveView` injects `@behaviour Phoenix.LiveView` exactly as the real one does,
  which is what gates the `:lv_reply` family. The navigation and stream functions record the
  *kind* of operation in the socket, so a thorough test could assert it — the demo's tests
  deliberately don't.
  """
  defstruct assigns: %{}, navigation: nil, stream_ops: [], pushed_events: []

  @type t :: %__MODULE__{}

  @callback mount(params :: map(), session :: map(), socket :: t()) :: term()
  @callback handle_event(event :: binary(), params :: map(), socket :: t()) :: term()

  @optional_callbacks mount: 3, handle_event: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour Phoenix.LiveView
    end
  end

  @doc "Record a *navigate* (remount a new LiveView). Kind observable in `socket.navigation`."
  def push_navigate(%__MODULE__{} = socket, opts), do: navigate(socket, {:navigate, opts})

  @doc "Record a *patch* (same process, re-run handle_params). Kind observable."
  def push_patch(%__MODULE__{} = socket, opts), do: navigate(socket, {:patch, opts})

  @doc "Record a full-page *redirect*. Kind observable."
  def redirect(%__MODULE__{} = socket, opts), do: navigate(socket, {:redirect, opts})

  defp navigate(socket, target), do: %{socket | navigation: target}

  @doc """
  Record a client *event* push. Whether the client was told anything is observable in
  `socket.pushed_events`, so a thorough test could assert it — the demo's test doesn't.
  """
  def push_event(%__MODULE__{} = socket, event, payload),
    do: %{socket | pushed_events: socket.pushed_events ++ [{event, payload}]}

  @doc "Record a stream *insert*. The op (`:insert`) is observable in `socket.stream_ops`."
  def stream_insert(%__MODULE__{} = socket, name, item),
    do: %{socket | stream_ops: socket.stream_ops ++ [{:insert, name, item}]}

  @doc "Record a stream *delete*. The op (`:delete`) is observable."
  def stream_delete(%__MODULE__{} = socket, name, item),
    do: %{socket | stream_ops: socket.stream_ops ++ [{:delete, name, item}]}

  @doc """
  Tell a child component to re-render with new assigns. Returns `:ok` (never the socket), and
  the notification lands in the caller's mailbox — so a thorough test could `assert_received`
  it; the demo's test deliberately doesn't.
  """
  def send_update(module, assigns) do
    send(self(), {:send_update, module, assigns})
    :ok
  end
end

defmodule Plug.Conn do
  @moduledoc "Tiny stand-in for `Plug.Conn`."
  defstruct status: nil, halted: false, assigns: %{}, resp_body: nil

  def put_status(%__MODULE__{} = conn, status), do: %{conn | status: status}
  def halt(%__MODULE__{} = conn), do: %{conn | halted: true}

  def assign(%__MODULE__{} = conn, key, value),
    do: %{conn | assigns: Map.put(conn.assigns, key, value)}
end

defmodule Phoenix.Controller do
  @moduledoc "Tiny stand-in for `Phoenix.Controller`."
  alias Plug.Conn

  @doc "Render a response body, keeping whatever status was set."
  def json(%Conn{} = conn, data), do: %{conn | resp_body: data}

  @doc """
  Record a redirect. The *kind* (`:to` vs `:external`) is observable in `resp_body`, so a
  thorough test could assert it — the demo's test deliberately doesn't.
  """
  def redirect(%Conn{} = conn, to: url), do: redirected(conn, {:to, url})
  def redirect(%Conn{} = conn, external: url), do: redirected(conn, {:external, url})

  defp redirected(conn, target), do: %{conn | status: :found, resp_body: {:redirect, target}}
end
