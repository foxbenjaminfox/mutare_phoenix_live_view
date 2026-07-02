defmodule Demo.SongsLive do
  @moduledoc """
  A LiveView whose whole observable contract is *which* socket transformation each callback
  performs — the navigation kind, the reply it sends back, the stream op it runs. These are
  precisely the calls a suite tends to under-assert, and each gap becomes a survivor.

  Written with a direct `@behaviour Phoenix.LiveView` — equivalent to the `@behaviour` that
  `use Phoenix.LiveView` injects, which is what gates `:lv_reply`. (Both forms are surfaced by
  `Mutare.Transform.Behaviours`; the direct form needs no `use`-expansion, so the demo is
  deterministic without a real `Phoenix.LiveView` to expand.)
  """
  @behaviour Phoenix.LiveView

  @doc """
  Initialise the view, declaring `:songs` as a *temporary* assign (reset after each render).
  Whether that option is actually set is observable — the test only checks that mount
  succeeded, so dropping it (`:lv_reply`) survives.
  """
  def mount(_params, _session, socket) do
    {:ok, socket, temporary_assigns: [songs: []]}
  end

  # "open" — a **navigate** (dismount this LiveView and mount the song's), *not* a patch. The
  # test only checks that *some* navigation happened, so swapping it for a patch (`:lv_nav`)
  # survives.
  def handle_event("open", %{"id" => id}, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/songs/" <> id)}
  end

  # "ping" — reply to a JS hook with a payload. The test only checks the socket comes back,
  # never the reply, so dropping the reply (`{:reply, _, socket}` → `{:noreply, socket}`,
  # `:lv_reply`) survives.
  def handle_event("ping", _params, socket) do
    {:reply, %{pong: true}, socket}
  end

  # "add" — add a song to the `:songs` stream, an **insert**. The test only checks the event
  # returned, never the stream contents, so inverting it to a delete (`:lv_stream`) survives.
  def handle_event("add", %{"name" => name}, socket) do
    {:noreply, Phoenix.LiveView.stream_insert(socket, :songs, %{id: name, name: name})}
  end

  # "select" — tell the client to highlight a row via a JS hook (`push_event`). The test only
  # checks the event returned `:noreply`, never that the client was told to highlight, so
  # dropping the push (`:lv_event`) survives.
  def handle_event("select", %{"id" => id}, socket) do
    {:noreply, Phoenix.LiveView.push_event(socket, "highlight", %{id: id})}
  end

  # "refresh" — tell the cart **component** to re-render with the new count (`send_update`), a
  # fire-and-forget message returning `:ok`, not the socket. The test only checks the event
  # returned `:noreply`, never that the component was notified, so removing the `send_update`
  # (it collapses to `:ok`) is invisible. `:lv_send_update` survives.
  def handle_event("refresh", %{"count" => count}, socket) do
    Phoenix.LiveView.send_update(Demo.CartComponent, id: "cart", count: count)
    {:noreply, socket}
  end
end
