defmodule Mutare.Phoenix.LiveView.ReplyTest do
  @moduledoc """
  `:lv_reply` — drops a LiveView callback's optional trailing element
  (`{:reply, payload, socket}` → `{:noreply, socket}`, `{:ok, socket, opts}` → `{:ok,
  socket}`), **gated on `@behaviour Phoenix.LiveView` / `Phoenix.LiveComponent`**. Delivered as
  the behaviour-aware structural return hook; inert in non-LiveView modules and on shapes with
  nothing to drop.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView.Reply

  defp reply_diffs(source), do: diffs_for(source, [Reply], :lv_reply)

  # A LiveView module via a direct `@behaviour Phoenix.LiveView` (no `use` expansion needed).
  defp live(body), do: "defmodule MyLive do\n  @behaviour Phoenix.LiveView\n\n#{body}\nend\n"

  # The component counterpart: a direct `@behaviour Phoenix.LiveComponent`.
  defp live_component(body),
    do: "defmodule MyComponent do\n  @behaviour Phoenix.LiveComponent\n\n#{body}\nend\n"

  describe "the reshape table (gated on @behaviour Phoenix.LiveView)" do
    test "handle_event {:reply, payload, socket} drops the reply -> :noreply" do
      assert reply_diffs(live("  def handle_event(_e, _p, s), do: {:reply, %{ok: true}, s}")) ==
               [{"{:reply, %{ok: true}, s}", "{:noreply, s}"}]
    end

    test "handle_call {:reply, reply, socket} drops the reply -> :noreply" do
      assert reply_diffs(live("  def handle_call(_m, _f, s), do: {:reply, :pong, s}")) ==
               [{"{:reply, :pong, s}", "{:noreply, s}"}]
    end

    test "mount {:ok, socket, opts} drops the options -> {:ok, socket}" do
      body = "  def mount(_p, _s, s), do: {:ok, s, temporary_assigns: [msgs: []]}"

      assert reply_diffs(live(body)) ==
               [{"{:ok, s, temporary_assigns: [msgs: []]}", "{:ok, s}"}]
    end

    test "a multi-statement body's reply tail is still reshaped" do
      body = """
        def handle_event(_e, _p, s) do
          s = assign(s, :count, 1)
          {:reply, %{count: 1}, s}
        end\
      """

      assert reply_diffs(live(body)) == [{"{:reply, %{count: 1}, s}", "{:noreply, s}"}]
    end

    test "each branch of a case in tail position is reshaped independently" do
      body = """
        def handle_event(_e, _p, s) do
          case s do
            %{ok: true} -> {:reply, %{a: 1}, s}
            _ -> {:reply, %{a: 2}, s}
          end
        end\
      """

      assert reply_diffs(live(body)) == [
               {"{:reply, %{a: 1}, s}", "{:noreply, s}"},
               {"{:reply, %{a: 2}, s}", "{:noreply, s}"}
             ]
    end
  end

  describe "the use Phoenix.LiveView path (use-injected behaviour)" do
    test "a `use Phoenix.LiveView` module is gated in too" do
      source = """
      defmodule MyLive do
        use Phoenix.LiveView
        def handle_event(_e, _p, s), do: {:reply, :pong, s}
      end
      """

      assert reply_diffs(source) == [{"{:reply, :pong, s}", "{:noreply, s}"}]
    end
  end

  describe "Phoenix.LiveComponent is gated in too (same {:reply, _, _} shape)" do
    test "a component's handle_event {:reply, payload, socket} drops the reply -> :noreply" do
      assert reply_diffs(
               live_component("  def handle_event(_e, _p, s), do: {:reply, %{ok: true}, s}")
             ) ==
               [{"{:reply, %{ok: true}, s}", "{:noreply, s}"}]
    end

    test "a `use Phoenix.LiveComponent` module is gated in via the injected behaviour" do
      source = """
      defmodule MyComponent do
        use Phoenix.LiveComponent
        def handle_event(_e, _p, s), do: {:reply, :pong, s}
      end
      """

      assert reply_diffs(source) == [{"{:reply, :pong, s}", "{:noreply, s}"}]
    end

    test "leaves a component's 2-tuple {:noreply, socket} untouched (nothing to drop)" do
      assert reply_diffs(live_component("  def handle_event(_e, _p, s), do: {:noreply, s}")) == []
    end
  end

  describe "scope" do
    test "does NOT fire in a non-LiveView module" do
      source = """
      defmodule Plain do
        def handle_event(_e, _p, s), do: {:reply, :pong, s}
      end
      """

      assert reply_diffs(source) == []
    end

    test "leaves a 2-tuple {:noreply, socket} untouched (nothing to drop)" do
      assert reply_diffs(live("  def handle_event(_e, _p, s), do: {:noreply, s}")) == []
    end

    test "leaves a 2-tuple {:ok, socket} untouched (nothing to drop)" do
      assert reply_diffs(live("  def mount(_p, _s, s), do: {:ok, s}")) == []
    end

    test "leaves an unrelated tagged tuple ({:error, reason}) untouched" do
      assert reply_diffs(live("  def mount(_p, _s, _s), do: {:error, :nope}")) == []
    end

    test "leaves a {:noreply, socket, continuation} 3-tuple untouched (no droppable reply)" do
      # A real LiveView return (e.g. `handle_info` with a `{:continue, …}`): a 3-tuple whose
      # tag is neither :reply nor :ok, so `returns_for/2` has no reshape and falls through.
      body = "  def handle_info(_m, s), do: {:noreply, s, {:continue, :load}}"
      assert reply_diffs(live(body)) == []
    end

    test "leaves a tuple with a computed (non-atom) tag untouched" do
      # The tag is a call, not a literal atom, so `tag_name/1` falls through to nil and no
      # reshape is offered — the tuple is left alone rather than crashing the scan.
      body = "  def handle_event(_e, _p, s), do: {reply_tag(), %{a: 1}, s}"
      assert reply_diffs(live(body)) == []
    end
  end

  describe "not duplicated by the built-in GenServer mutator (different behaviour gate)" do
    test "the GenServer mutator does NOT fire on a LiveView's {:reply, _, _}" do
      source = """
      defmodule MyLive do
        @behaviour Phoenix.LiveView
        def handle_call(_m, _f, s), do: {:reply, :pong, s}
      end
      """

      # `:genserver` is gated on @behaviour GenServer, absent here — so only `:lv_reply` fires.
      genserver_pairs = diffs_for(source, [Reply, Mutare.Mutators.GenServer], :genserver)
      assert genserver_pairs == []

      assert diffs_for(source, [Reply, Mutare.Mutators.GenServer], :lv_reply) == [
               {"{:reply, :pong, s}", "{:noreply, s}"}
             ]
    end
  end

  test "every embedded mutant is a valid LiveView return that compiles" do
    source = """
    defmodule ReplyCompileDemo do
      @behaviour Phoenix.LiveView

      def mount(_p, _s, socket), do: {:ok, socket, temporary_assigns: [items: []]}
      def handle_event(_e, _p, socket), do: {:reply, %{ok: true}, socket}
    end
    """

    assert_metamutant_compiles(source, [Reply])
  end
end
