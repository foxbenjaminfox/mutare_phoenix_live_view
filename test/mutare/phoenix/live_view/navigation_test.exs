defmodule Mutare.Phoenix.LiveView.NavigationTest do
  @moduledoc """
  `:lv_nav` — swaps the socket-navigation call between `push_navigate` ↔ `push_patch`.
  Pipe-aware (`mutate/2`): the rename only fires for the arity-2 form both functions share, so
  the swap stays compile-safe and the effective arity is recovered through pipe context. Matches
  direct, aliased, and bare-imported (`use`-style) forms; `redirect` is never a source. Also
  carries the defensive LiveView-DSL `:skip` registration.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.CallRouting.Spec
  alias Mutare.CallRouting.Registry
  alias Mutare.Phoenix.LiveView.Navigation

  defp nav_diffs(source), do: diffs_for(source, [Navigation], :lv_nav)

  # The per-position treatment list a `module_key`/`name`/`arity` call matches in `registry`,
  # or `nil` when unregistered. `Registry.lookup/4` returns the matched `%Entry{}` carrying
  # its `%Spec{}`; `Spec.routing/2` expands its (static `:skip`) treatment over the arity.
  defp routing(registry, module_key, name, arity) do
    case Registry.lookup(registry, module_key, name, arity) do
      nil -> nil
      entry -> Spec.routing(entry.spec, arity)
    end
  end

  # Wrap a body in a LiveView module that imports `Phoenix.LiveView`, the `use …, :live_view`
  # form (so bare `push_navigate`/`push_patch` resolve).
  defp live(body), do: "defmodule MyLive do\n  import Phoenix.LiveView\n\n#{body}\nend\n"

  describe "push_navigate — the headline (navigate <-> patch)" do
    test "a qualified push_navigate offers push_patch" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_navigate(s, to: \"/next\")\nend\n"

      assert nav_diffs(source) == [
               {"Phoenix.LiveView.push_navigate(s, to: \"/next\")",
                "Phoenix.LiveView.push_patch(s, to: \"/next\")"}
             ]
    end

    test "a bare imported push_navigate (use-style) swaps to push_patch" do
      assert nav_diffs(live("  def go(s), do: push_navigate(s, to: \"/next\")")) == [
               {"push_navigate(s, to: \"/next\")", "push_patch(s, to: \"/next\")"}
             ]
    end
  end

  describe "push_patch — patch back to navigate only" do
    test "a qualified push_patch offers push_navigate" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_patch(s, to: \"/here\")\nend\n"

      assert nav_diffs(source) ==
               [
                 {"Phoenix.LiveView.push_patch(s, to: \"/here\")",
                  "Phoenix.LiveView.push_navigate(s, to: \"/here\")"}
               ]
    end
  end

  describe "written forms" do
    test "an aliased LV.push_navigate swaps, keeping the alias" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s), do: LV.push_navigate(s, to: "/x")
      end
      """

      assert nav_diffs(source) == [
               {"LV.push_navigate(s, to: \"/x\")", "LV.push_patch(s, to: \"/x\")"}
             ]
    end

    test "a piped stage swaps the name, keeping the pipe" do
      assert nav_diffs(live("  def go(s), do: s |> push_patch(to: \"/x\")")) ==
               [{"push_patch(to: \"/x\")", "push_navigate(to: \"/x\")"}]
    end
  end

  describe "scope" do
    test "redirect is not a source for :lv_nav (its to:/external: kind is a different axis)" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.redirect(s, to: \"/x\")\nend\n"

      assert nav_diffs(source) == []
    end

    test "a non-navigation Phoenix.LiveView call is untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.put_flash(s, :info, \"hi\")\nend\n"

      assert nav_diffs(source) == []
    end

    test "a same-named local push_navigate (no import, no qualifier) is not swapped" do
      source = """
      defmodule L do
        def go(s), do: push_navigate(s, to: "/x")
        def push_navigate(s, _o), do: s
      end
      """

      assert nav_diffs(source) == []
    end
  end

  describe "the arity-2 guard (compile-safety, recovered through pipe context)" do
    test "a qualified non-arity-2 push_navigate is left alone" do
      source =
        "defmodule L do\n  def go(s, x), do: Phoenix.LiveView.push_navigate(s, [to: \"/x\"], x)\nend\n"

      assert nav_diffs(source) == []
    end
  end

  describe "call_routes/0 — the defensive LiveView DSL :skip (whole calls)" do
    test "registers the live route DSL so core leaves route declarations raw" do
      registry = Registry.build([], Mutare.Mutators.resolve([Navigation]))

      assert routing(registry, [:Phoenix, :LiveView, :Router], :live, 3) == :skip

      assert routing(registry, [:Phoenix, :LiveView, :Router], :live_session, 2) == :skip

      assert routing(registry, [:Phoenix, :LiveView], :on_mount, 1) == :skip

      # An unregistered name is unaffected — the mutated runtime calls stay reachable.
      assert routing(registry, [:Phoenix, :LiveView], :push_navigate, 2) == nil
      assert routing(registry, [:Phoenix, :LiveView, :Router], :unknown, 1) == nil
    end

    test "registers the declarative-assigns DSL (attr/slot/embed_templates)" do
      registry = Registry.build([], Mutare.Mutators.resolve([Navigation]))

      assert routing(registry, [:Phoenix, :Component], :attr, 3) == :skip
      assert routing(registry, [:Phoenix, :Component], :slot, 2) == :skip
      assert routing(registry, [:Phoenix, :Component], :embed_templates, 1) == :skip
    end

    test "every registered entry targets the LiveView DSL and skips the call at any arity" do
      dsl_modules = [Phoenix.LiveView.Router, Phoenix.LiveView, Phoenix.Component]

      assert Enum.all?(Navigation.call_routes(), fn
               {module, name, :any, :skip} -> module in dsl_modules and is_atom(name)
               _other -> false
             end)
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified push_navigate yields push_patch only" do
      assert node_mutations("Phoenix.LiveView.push_navigate(s, to: p)", Navigation) == [
               "Phoenix.LiveView.push_patch(s, to: p)"
             ]
    end

    test "node-local mutate/1 never fires (it has no pipe context for the arity guard)" do
      node = Mutare.AST.parse!("Phoenix.LiveView.push_navigate(s, to: p)")
      assert Navigation.mutate(node) == :skip
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule NavCompileDemo do
      import Phoenix.LiveView

      def go(socket) do
        socket
        |> push_navigate(to: "/dashboard")
        |> push_patch(to: "/dashboard")
      end
    end
    """

    assert_metamutant_compiles(source, [Navigation])
  end
end
