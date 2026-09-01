defmodule Mutare.Phoenix.LiveViewTest do
  @moduledoc """
  The package's preset (`all/0`, the six LiveView families) and a cross-family integration
  check: a realistic LiveView + auth-hook + controller surface mutated by every family — the
  six LiveView families, the three base families it is composed with, and the built-in
  `:convention` that covers the auth `:cont`/`:halt` swap — recording the expected names and
  compiling as one metamutant.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView, as: LV

  doctest Mutare.Phoenix.LiveView

  describe "preset" do
    test "all/0 is the six LiveView families" do
      assert LV.all() ==
               [
                 Mutare.Phoenix.LiveView.Navigation,
                 Mutare.Phoenix.LiveView.Reply,
                 Mutare.Phoenix.LiveView.Stream,
                 Mutare.Phoenix.LiveView.Event,
                 Mutare.Phoenix.LiveView.SendUpdate,
                 Mutare.Phoenix.LiveView.Hook
               ]
    end

    test "every preset entry resolves as a Mutare.Mutator" do
      for module <- LV.all() do
        assert Mutare.Mutator.Dispatch.implemented_by?(module)
      end
    end

    test "all/0 resolves via Mutare.Mutators.resolve/1 to the six recorded family names" do
      assert Enum.map(Mutare.Mutators.resolve(LV.all()), & &1.name) ==
               [:lv_nav, :lv_reply, :lv_stream, :lv_event, :lv_send_update, :lv_hook]
    end

    test "composed with the base preset, it splices into a :mutators list and resolves in order" do
      # `:convention` is the built-in family this file leans on elsewhere (the auth
      # `:cont`/`:halt` swap), so it stands in for the `:builtins` group the moduledoc's
      # `.mutare.exs` examples splice these presets alongside. The base package's family list
      # is read off its own preset rather than repeated here — this test pins the *splicing*
      # (everything resolves, in order), not `mutare_phoenix`'s registry.
      specs = Mutare.Mutators.resolve([:convention] ++ Mutare.Phoenix.all() ++ LV.all())
      base_names = Enum.map(Mutare.Mutators.resolve(Mutare.Phoenix.all()), & &1.name)

      assert Enum.map(specs, & &1.name) ==
               [:convention] ++
                 base_names ++
                 [:lv_nav, :lv_reply, :lv_stream, :lv_event, :lv_send_update, :lv_hook]
    end
  end

  describe "integration across families" do
    @surface """
    defmodule DemoWeb.PageLive do
      @behaviour Phoenix.LiveView

      def mount(_params, _session, socket) do
        socket = Phoenix.LiveView.attach_hook(socket, :log, :handle_event, &log_hook/3)
        {:ok, socket, temporary_assigns: [items: []]}
      end

      def handle_event("nav", _params, socket) do
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/next")}
      end

      def handle_event("ping", _params, socket) do
        {:reply, %{pong: true}, Phoenix.LiveView.push_event(socket, "pong", %{})}
      end

      def handle_event("add", %{"name" => name}, socket) do
        {:noreply, Phoenix.LiveView.stream_insert(socket, :songs, name)}
      end

      def handle_info({:refresh, id}, socket) do
        Phoenix.LiveView.send_update(DemoWeb.CartComponent, id: id, count: 0)
        {:noreply, socket}
      end

      defp log_hook(_event, _params, socket), do: {:cont, socket}
    end

    defmodule DemoWeb.UserAuth do
      def on_mount(:default, _params, session, socket) do
        if session["user_id"] do
          {:cont, socket}
        else
          {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
        end
      end
    end

    defmodule DemoWeb.PageController do
      def show(conn, _params) do
        conn
        |> Plug.Conn.put_status(:ok)
        |> Phoenix.Controller.redirect(to: "/welcome")
      end

      def block(conn, _params) do
        conn
        |> Plug.Conn.put_status(:unauthorized)
        |> Plug.Conn.halt()
      end
    end
    """

    test "every package family fires on the surface it owns" do
      names =
        @surface
        |> diffs(Mutare.Phoenix.all() ++ LV.all())
        |> Enum.map(&elem(&1, 0))
        |> MapSet.new()

      package_families =
        MapSet.new([
          :http_status,
          :lv_event,
          :lv_hook,
          :lv_nav,
          :lv_reply,
          :lv_send_update,
          :lv_stream,
          :plug_halt
        ])

      # All eight package families fire (the transform also records structural siblings like
      # `:clause_drop` on the multi-clause `handle_event`, so this is a subset check).
      assert MapSet.subset?(package_families, names)
    end

    test "the auth :cont/:halt swap comes from the built-in :convention (no package family)" do
      convention_pairs = diffs_for(@surface, [:convention], :convention)

      # The `on_mount` hook's decision, both directions — `:convention` matches the atom
      # literal itself, so the recorded diff is the bare atom (the rejection-path flip
      # `:halt` -> `:cont` is the marquee auth mutation; no package family is involved).
      assert {":halt", ":cont"} in convention_pairs
      assert {":cont", ":halt"} in convention_pairs
    end

    test "the whole surface compiles as one metamutant, built-ins included" do
      mutators = Mutare.Mutators.all() ++ Mutare.Phoenix.all() ++ LV.all()
      assert_metamutant_compiles(@surface, mutators)
    end
  end
end
