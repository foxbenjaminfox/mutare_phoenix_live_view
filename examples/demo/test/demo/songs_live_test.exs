defmodule Demo.SongsLiveTest do
  use ExUnit.Case

  alias Demo.SongsLive

  defp socket, do: %Phoenix.LiveView{}

  # The gaps below are deliberate — the *ordinary* gaps a competent-but-not-paranoid suite
  # leaves, each of which becomes a Mutare survivor.

  # Asserts mount *succeeded* but never that it set the `temporary_assigns` option — so
  # dropping the option (`{:ok, s, opts}` → `{:ok, s}`) is invisible. `:lv_reply` survives.
  test "mount succeeds" do
    assert elem(SongsLive.mount(%{}, %{}, socket()), 0) == :ok
  end

  # Asserts that *some* navigation happened, never its kind — so turning the navigate into a
  # patch (state kept instead of remounted) is invisible. `:lv_nav` survives.
  test "open navigates somewhere" do
    {:noreply, socket} = SongsLive.handle_event("open", %{"id" => "7"}, socket())
    assert socket.navigation != nil
  end

  # Asserts only that the socket comes back, never the reply payload — so dropping the reply
  # (`{:reply, _, s}` → `{:noreply, s}`) is invisible. `:lv_reply` survives. (The socket is
  # always the tuple's last element, so this assertion holds for both arities.)
  test "ping returns the socket unchanged" do
    result = SongsLive.handle_event("ping", %{}, socket())
    assert elem(result, tuple_size(result) - 1) == socket()
  end

  # Asserts only that the event returned `:noreply`, never the stream contents — so inverting
  # the insert into a delete is invisible. `:lv_stream` survives.
  test "add returns noreply" do
    assert {:noreply, _socket} = SongsLive.handle_event("add", %{"name" => "Stella"}, socket())
  end

  # Asserts only that the event returned `:noreply`, never that the client was told to
  # highlight — so dropping the push_event entirely is invisible. `:lv_event` survives.
  test "select returns noreply" do
    assert {:noreply, _socket} = SongsLive.handle_event("select", %{"id" => "7"}, socket())
  end

  # Asserts only that the event returned `:noreply`, never that the cart component was notified
  # to re-render — so removing the send_update (it collapses to `:ok`) is invisible.
  # `:lv_send_update` survives.
  test "refresh returns noreply" do
    assert {:noreply, _socket} = SongsLive.handle_event("refresh", %{"count" => 2}, socket())
  end
end
