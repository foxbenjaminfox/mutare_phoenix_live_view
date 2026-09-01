defmodule Mutare.Phoenix.LiveView.HookTest do
  @moduledoc """
  `:lv_hook` — removes a lifecycle-hook management call, pipe-aware: non-piped → the socket,
  piped → `Function.identity()`. Two variant-labelled kinds: `attach` (`attach_hook/4` — the
  hook never runs) and `detach` (`detach_hook/3` — the hook keeps running). The hook name and
  stage arguments are pinned with the shared `:structural` mark, so core's value families
  leave those identifiers alone. Matches direct, aliased, and bare-imported (`use`-style)
  forms.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView.Hook

  defp hook_diffs(source), do: diffs_for(source, [Hook], :lv_hook)

  defp live(body), do: "defmodule MyLive do\n  import Phoenix.LiveView\n\n#{body}\nend\n"

  describe "removal across written forms" do
    test "a qualified Phoenix.LiveView.attach_hook collapses to the socket" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.attach_hook(s, :log, :handle_event, &h/3)\nend\n"

      assert hook_diffs(source) ==
               [{"Phoenix.LiveView.attach_hook(s, :log, :handle_event, &h/3)", "s"}]
    end

    test "a bare imported attach_hook (use-style) collapses to the socket" do
      assert hook_diffs(live("  def go(s), do: attach_hook(s, :log, :handle_event, &h/3)")) ==
               [{"attach_hook(s, :log, :handle_event, &h/3)", "s"}]
    end

    test "an aliased LV.attach_hook collapses to the socket" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s), do: LV.attach_hook(s, :log, :handle_event, &h/3)
      end
      """

      assert hook_diffs(source) == [{"LV.attach_hook(s, :log, :handle_event, &h/3)", "s"}]
    end

    test "detach_hook/3 collapses to the socket (the hook keeps running)" do
      assert hook_diffs(live("  def go(s), do: detach_hook(s, :log, :handle_event)")) ==
               [{"detach_hook(s, :log, :handle_event)", "s"}]
    end

    test "a string hook name is removed the same way" do
      assert hook_diffs(live("  def go(s), do: attach_hook(s, \"log\", :handle_info, &h/3)")) ==
               [{"attach_hook(s, \"log\", :handle_info, &h/3)", "s"}]
    end
  end

  describe "pipe awareness" do
    test "a piped attach_hook stage becomes the identity no-op" do
      body = "  def go(s), do: s |> attach_hook(:log, :handle_event, &h/3)"

      assert hook_diffs(live(body)) ==
               [{"attach_hook(:log, :handle_event, &h/3)", "Elixir.Function.identity()"}]
    end

    test "a piped detach_hook stage becomes the identity no-op" do
      assert hook_diffs(live("  def go(s), do: s |> detach_hook(:log, :handle_event)")) ==
               [{"detach_hook(:log, :handle_event)", "Elixir.Function.identity()"}]
    end

    test "attach_hook mid-chain is still removed" do
      body = "  def go(s), do: s |> attach_hook(:log, :handle_event, &h/3) |> assign(:x, 1)"

      assert hook_diffs(live(body)) ==
               [{"attach_hook(:log, :handle_event, &h/3)", "Elixir.Function.identity()"}]
    end
  end

  describe "the structural mark on hook name and stage" do
    test "core's AtomLiteral leaves the name and stage atoms alone when this family is enabled" do
      source = live("  def go(s), do: attach_hook(s, :log, :handle_event, &h/3)")

      assert diffs(source, [Mutare.Mutators.AtomLiteral, Hook]) ==
               [{:lv_hook, "attach_hook(s, :log, :handle_event, &h/3)", "s"}]
    end

    test "detach_hook's identifiers are pinned the same way" do
      source = live("  def go(s), do: detach_hook(s, :log, :handle_event)")

      assert diffs(source, [Mutare.Mutators.AtomLiteral, Hook]) ==
               [{:lv_hook, "detach_hook(s, :log, :handle_event)", "s"}]
    end

    test "control: without this family the sentinel mutants do fire on those identifiers" do
      source = live("  def go(s), do: attach_hook(s, :log, :handle_event, &h/3)")

      assert diffs(source, [Mutare.Mutators.AtomLiteral]) ==
               [{:atom, ":log", ":mutare"}, {:atom, ":handle_event", ":mutare"}]
    end
  end

  describe "variant labels (# mutare:ignore[lv_hook:<kind>])" do
    test "the declared vocabulary" do
      assert Hook.variants() == ["attach", "detach"]
    end

    test "a qualified directive suppresses one kind and leaves the other live" do
      source =
        live("""
          def go(s) do
            s
            |> attach_hook(:log, :handle_event, &h/3) # mutare:ignore[lv_hook:attach]
            |> detach_hook(:log, :handle_event)
          end
        """)

      result = Mutare.transform_string(source, mutators: [Hook])

      assert Enum.map(result.mutants, &{&1.variant, &1.ignored}) ==
               [{["attach"], true}, {["detach"], false}]
    end
  end

  describe "scope" do
    test "leaves other Phoenix.LiveView calls untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_patch(s, to: \"/x\")\nend\n"

      assert hook_diffs(source) == []
    end

    test "a wrong-arity qualified attach_hook is left alone (the arity guard)" do
      three =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.attach_hook(s, :log, :handle_event)\nend\n"

      five =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.attach_hook(s, :log, :handle_event, &h/3, :x)\nend\n"

      assert hook_diffs(three) == []
      assert hook_diffs(five) == []
    end

    test "a wrong-arity qualified detach_hook is left alone" do
      two = "defmodule L do\n  def go(s), do: Phoenix.LiveView.detach_hook(s, :log)\nend\n"

      four =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.detach_hook(s, :log, :handle_event, :x)\nend\n"

      assert hook_diffs(two) == []
      assert hook_diffs(four) == []
    end

    test "does not remove a same-named local attach_hook (no import, no qualifier)" do
      source = """
      defmodule L do
        def go(s), do: attach_hook(s, :log, :handle_event, &h/3)
        def attach_hook(s, _n, _st, _f), do: s
        def h(_e, _p, s), do: {:cont, s}
      end
      """

      assert hook_diffs(source) == []
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified attach_hook removes to its first argument" do
      assert node_mutations("Phoenix.LiveView.attach_hook(s, :log, :handle_event, &h/3)", Hook) ==
               ["s"]
    end

    test "a piped stage node yields the identity no-op" do
      assert node_mutations("Phoenix.LiveView.detach_hook(:log, :handle_event)", Hook, :piped) ==
               ["Elixir.Function.identity()"]
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      node = Mutare.AST.parse!("Phoenix.LiveView.attach_hook(s, :log, :handle_event, &h/3)")
      assert Hook.mutate(node) == :skip
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule HookCompileDemo do
      import Phoenix.LiveView

      def mount_hooks(socket) do
        socket
        |> attach_hook(:log, :handle_event, &log_hook/3)
        |> attach_hook(:timer, :handle_info, fn _msg, s -> {:cont, s} end)
      end

      def stop_logging(socket) do
        detach_hook(socket, :log, :handle_event)
      end

      defp log_hook(_event, _params, socket), do: {:cont, socket}
    end
    """

    assert_metamutant_compiles(source, [Hook])
  end
end
