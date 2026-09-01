defmodule Mutare.Phoenix.LiveView.SendUpdateTest do
  @moduledoc """
  `:lv_send_update` — two variant-labelled kinds on the `Phoenix.LiveView` component-update
  calls (the `LiveComponent` sibling of `:lv_event`'s dropped client push). `remove` drops the
  call: neither returns the socket, so it collapses to a happy-path return — `send_update/2,3`
  to the stand-in `:ok`, `send_update_after/3,4` to a fresh `:erlang.make_ref()`. `immediate`
  keeps the update but drops `send_update_after`'s delay — a `send_update` now, followed by a
  fresh ref so the expression keeps the documented `reference()` type. Matches direct, aliased,
  and bare-imported (`use`-style) forms; the never-idiomatic piped form is left alone.
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView.SendUpdate

  defp su_diffs(source), do: diffs_for(source, [SendUpdate], :lv_send_update)

  defp live(body), do: "defmodule MyLive do\n  import Phoenix.LiveView\n\n#{body}\nend\n"

  describe "removal across written forms" do
    test "a qualified Phoenix.LiveView.send_update collapses to :ok" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.send_update(Cart, id: 1)\nend\n"

      assert su_diffs(source) == [{"Phoenix.LiveView.send_update(Cart, id: 1)", ":ok"}]
    end

    test "a bare imported send_update (use-style) collapses to :ok" do
      assert su_diffs(live("  def go(s), do: send_update(Cart, id: 1, count: 3)")) ==
               [{"send_update(Cart, id: 1, count: 3)", ":ok"}]
    end

    test "an aliased LV.send_update collapses to :ok" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s), do: LV.send_update(Cart, id: 1)
      end
      """

      assert su_diffs(source) == [{"LV.send_update(Cart, id: 1)", ":ok"}]
    end

    test "the arity-3 pid form send_update(pid, module, assigns) collapses to :ok" do
      assert su_diffs(live("  def go(pid), do: send_update(pid, Cart, id: 1)")) ==
               [{"send_update(pid, Cart, id: 1)", ":ok"}]
    end

    test "send_update_after/3 collapses to a fresh :erlang.make_ref() (its real return)" do
      assert {"send_update_after(Cart, [id: 1], 1000)", ":erlang.make_ref()"} in su_diffs(
               live("  def go(s), do: send_update_after(Cart, [id: 1], 1000)")
             )
    end

    test "the arity-4 pid form send_update_after collapses to a fresh reference" do
      assert {"send_update_after(pid, Cart, [id: 1], 1000)", ":erlang.make_ref()"} in su_diffs(
               live("  def go(pid), do: send_update_after(pid, Cart, [id: 1], 1000)")
             )
    end
  end

  describe "the immediate kind (send_update_after drops its delay)" do
    test "send_update_after/3 also becomes an immediate send_update plus the ref" do
      assert su_diffs(live("  def go(s), do: send_update_after(Cart, [id: 1], 1000)")) ==
               [
                 {"send_update_after(Cart, [id: 1], 1000)", ":erlang.make_ref()"},
                 {"send_update_after(Cart, [id: 1], 1000)",
                  "send_update(Cart, id: 1)\n:erlang.make_ref()"}
               ]
    end

    test "the arity-4 pid form keeps the pid on the immediate send_update/3" do
      assert {"send_update_after(pid, Cart, [id: 1], 1000)",
              "send_update(pid, Cart, id: 1)\n:erlang.make_ref()"} in su_diffs(
               live("  def go(pid), do: send_update_after(pid, Cart, [id: 1], 1000)")
             )
    end

    test "a qualified call keeps its qualifier on the immediate sibling" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.send_update_after(Cart, [id: 1], 5)\nend\n"

      assert {"Phoenix.LiveView.send_update_after(Cart, [id: 1], 5)",
              "Phoenix.LiveView.send_update(Cart, id: 1)\n:erlang.make_ref()"} in su_diffs(source)
    end

    test "an aliased call keeps its alias on the immediate sibling" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s), do: LV.send_update_after(Cart, [id: 1], 5)
      end
      """

      assert {"LV.send_update_after(Cart, [id: 1], 5)",
              "LV.send_update(Cart, id: 1)\n:erlang.make_ref()"} in su_diffs(source)
    end
  end

  describe "the delay is a marked :timeout position" do
    test "core's IntegerLiteral leaves the delay literal alone when this family is enabled" do
      source = live("  def go(s), do: send_update_after(Cart, [id: 1], 1000)")
      all = diffs(source, [Mutare.Mutators.IntegerLiteral, SendUpdate])

      # The `immediate` mutant owns the timing question; the `1000 → 1001` off-by-one would be
      # the near-unkillable duration noise core's own timeout table exists to avoid. The
      # assigns' `id: 1` literal is ordinary data and still mutates.
      refute Enum.any?(all, fn {family, original, _mutated} ->
               family == :integer and original == "1000"
             end)

      assert {:integer, "1", "2"} in all
    end

    test "control: without this family the delay literal is mutated" do
      source = live("  def go(s), do: send_update_after(Cart, [id: 1], 1000)")

      assert {:integer, "1000", "1001"} in diffs(source, [Mutare.Mutators.IntegerLiteral])
    end
  end

  describe "variant labels (# mutare:ignore[lv_send_update:<kind>])" do
    test "the declared vocabulary" do
      assert SendUpdate.variants() == ["remove", "immediate"]
    end

    test "a qualified directive suppresses one kind and leaves the other live" do
      source =
        live(
          "  def go(s), do: send_update_after(Cart, [id: 1], 1000) # mutare:ignore[lv_send_update:immediate]"
        )

      result = Mutare.transform_string(source, mutators: [SendUpdate])

      assert Enum.map(result.mutants, &{&1.variant, &1.ignored}) ==
               [{["remove"], false}, {["immediate"], true}]
    end
  end

  describe "pipe awareness" do
    test "a piped send_update is left alone (no faithful pass-through, never idiomatic)" do
      assert su_diffs(live("  def go(s), do: s |> send_update(id: 1)")) == []
    end

    test "a piped send_update_after is left alone" do
      assert su_diffs(live("  def go(s), do: s |> send_update_after([id: 1], 1000)")) == []
    end
  end

  describe "scope" do
    test "leaves other Phoenix.LiveView calls untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_event(s, \"ping\", %{})\nend\n"

      assert su_diffs(source) == []
    end

    test "a wrong-arity qualified send_update is left alone (the arity guard)" do
      one = "defmodule L do\n  def go, do: Phoenix.LiveView.send_update(Cart)\nend\n"

      four =
        "defmodule L do\n  def go(p), do: Phoenix.LiveView.send_update(p, Cart, [], :x)\nend\n"

      assert su_diffs(one) == []
      assert su_diffs(four) == []
    end

    test "a wrong-arity qualified send_update_after is left alone" do
      two = "defmodule L do\n  def go, do: Phoenix.LiveView.send_update_after(Cart, [])\nend\n"

      five =
        "defmodule L do\n  def go(p), do: Phoenix.LiveView.send_update_after(p, C, [], 1, 2)\nend\n"

      assert su_diffs(two) == []
      assert su_diffs(five) == []
    end

    test "does not remove a same-named local send_update (no import, no qualifier)" do
      source = """
      defmodule L do
        def go(s), do: send_update(Cart, id: 1)
        def send_update(_m, _a), do: :ok
      end
      """

      assert su_diffs(source) == []
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified send_update collapses to :ok" do
      assert node_mutations("Phoenix.LiveView.send_update(Cart, id: 1)", SendUpdate) == [":ok"]
    end

    test "qualified send_update_after yields the removal and the immediate sibling" do
      assert node_mutations("Phoenix.LiveView.send_update_after(Cart, [id: 1], 1)", SendUpdate) ==
               [
                 ":erlang.make_ref()",
                 "Phoenix.LiveView.send_update(Cart, id: 1)\n:erlang.make_ref()"
               ]
    end

    test "a piped stage node yields nothing (piped is left alone)" do
      assert node_mutations("Phoenix.LiveView.send_update(id: 1)", SendUpdate, :piped) == []
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      assert SendUpdate.mutate(Mutare.AST.parse!("Phoenix.LiveView.send_update(Cart, id: 1)")) ==
               :skip
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule SendUpdateCompileDemo do
      import Phoenix.LiveView

      def refresh(pid) do
        send_update(Cart, id: "cart", count: 3)
        send_update(pid, Cart, id: "cart")
        send_update_after(Cart, [id: "cart"], 1_000)
        send_update_after(pid, Cart, [id: "cart"], 500)
        :ok
      end

      def capture do
        ref = send_update_after(Cart, [id: "cart"], 1_000)
        Process.cancel_timer(ref)
      end

      # Awkward value positions: the two-expression `immediate` block must stay compile-safe
      # even as a pipe head or a call argument.
      def awkward(m) do
        send_update_after(Cart, [id: "cart"], 100) |> then(&Map.put(m, :ref, &1))
        Map.put(m, :ref, send_update_after(Cart, [id: "cart"], 100))
      end
    end
    """

    assert_metamutant_compiles(source, [SendUpdate])
  end
end
