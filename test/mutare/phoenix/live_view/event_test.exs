defmodule Mutare.Phoenix.LiveView.EventTest do
  @moduledoc """
  `:lv_event` — removes `Phoenix.LiveView.push_event/3` (the "forgot to push a client event"
  removal, the LiveView sibling of `:plug_halt`), pipe-aware: non-piped → the socket, piped →
  `Function.identity()`. Matches direct, aliased, and bare-imported (`use`-style) forms.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView.Event

  defp event_diffs(source), do: diffs_for(source, [Event], :lv_event)

  defp live(body), do: "defmodule MyLive do\n  import Phoenix.LiveView\n\n#{body}\nend\n"

  describe "removal across written forms" do
    test "a qualified Phoenix.LiveView.push_event collapses to the socket" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_event(s, \"ping\", %{})\nend\n"

      assert event_diffs(source) ==
               [{"Phoenix.LiveView.push_event(s, \"ping\", %{})", "s"}]
    end

    test "a bare imported push_event (use-style) collapses to the socket" do
      assert event_diffs(live("  def go(s), do: push_event(s, \"ping\", %{})")) ==
               [{"push_event(s, \"ping\", %{})", "s"}]
    end

    test "an aliased LV.push_event collapses to the socket" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s), do: LV.push_event(s, "ping", %{})
      end
      """

      assert event_diffs(source) == [{"LV.push_event(s, \"ping\", %{})", "s"}]
    end
  end

  describe "pipe awareness" do
    test "a piped stage becomes the identity no-op (the only compile-safe removal)" do
      assert event_diffs(live("  def go(s), do: s |> push_event(\"ping\", %{})")) ==
               [{"push_event(\"ping\", %{})", "Elixir.Function.identity()"}]
    end

    test "push_event mid-chain is still removed" do
      body = "  def go(s), do: s |> push_event(\"a\", %{}) |> assign(:x, 1)"
      assert event_diffs(live(body)) == [{"push_event(\"a\", %{})", "Elixir.Function.identity()"}]
    end
  end

  describe "scope" do
    test "leaves other Phoenix.LiveView calls untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_patch(s, to: \"/x\")\nend\n"

      assert event_diffs(source) == []
    end

    test "a non-arity-3 qualified push_event is left alone (the arity guard)" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_event(s, \"ping\")\nend\n"

      assert event_diffs(source) == []
    end

    test "does not remove a same-named local push_event (no import, no qualifier)" do
      source = """
      defmodule L do
        def go(s), do: push_event(s, "ping", %{})
        def push_event(s, _e, _p), do: s
      end
      """

      assert event_diffs(source) == []
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified push_event removes to its first argument" do
      assert node_mutations("Phoenix.LiveView.push_event(s, \"e\", %{})", Event) == ["s"]
    end

    test "a piped stage node yields the identity no-op" do
      assert node_mutations("Phoenix.LiveView.push_event(\"e\", %{})", Event, :piped) == [
               "Elixir.Function.identity()"
             ]
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      assert Event.mutate(Mutare.AST.parse!("Phoenix.LiveView.push_event(s, \"e\", %{})")) ==
               :skip
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule EventCompileDemo do
      import Phoenix.LiveView

      def go(socket) do
        socket
        |> push_event("highlight", %{id: 1})
        |> push_event("scroll", %{to: "top"})
      end
    end
    """

    assert_metamutant_compiles(source, [Event])
  end
end
