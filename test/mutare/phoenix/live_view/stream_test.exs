defmodule Mutare.Phoenix.LiveView.StreamTest do
  @moduledoc """
  `:lv_stream` — three kinds, each variant-labelled: `swap` inverts `stream_insert` ↔
  `stream_delete` (only the 3-arg form both functions share, because `stream_delete` has no
  arity-4); `at` swaps `stream_insert/4`'s `at: 0` ↔ `at: -1` boundary positions (substituting
  exactly the value node, so core's Overlap pass prunes `IntegerLiteral`'s redundant leaves
  there); `limit` drops the `limit:` entry from `stream/4` / `stream_insert/4` (the unbounded
  stream). All pipe-aware (`mutate/2`).
  """
  use ExUnit.Case, async: true

  import Mutare.Test

  alias Mutare.Phoenix.LiveView.Stream, as: StreamMut

  defp stream_diffs(source), do: diffs_for(source, [StreamMut], :lv_stream)

  defp live(body), do: "defmodule MyLive do\n  import Phoenix.LiveView\n\n#{body}\nend\n"

  describe "the insert ↔ delete swap (arity-3 form)" do
    test "a qualified stream_insert/3 becomes stream_delete" do
      source =
        "defmodule L do\n  def go(s, x), do: Phoenix.LiveView.stream_insert(s, :songs, x)\nend\n"

      assert stream_diffs(source) ==
               [
                 {"Phoenix.LiveView.stream_insert(s, :songs, x)",
                  "Phoenix.LiveView.stream_delete(s, :songs, x)"}
               ]
    end

    test "a qualified stream_delete/3 becomes stream_insert" do
      source =
        "defmodule L do\n  def go(s, x), do: Phoenix.LiveView.stream_delete(s, :songs, x)\nend\n"

      assert stream_diffs(source) ==
               [
                 {"Phoenix.LiveView.stream_delete(s, :songs, x)",
                  "Phoenix.LiveView.stream_insert(s, :songs, x)"}
               ]
    end

    test "a bare imported stream_insert (use-style) swaps" do
      assert stream_diffs(live("  def go(s, x), do: stream_insert(s, :songs, x)")) ==
               [{"stream_insert(s, :songs, x)", "stream_delete(s, :songs, x)"}]
    end

    test "an aliased LV.stream_insert swaps, keeping the alias" do
      source = """
      defmodule L do
        alias Phoenix.LiveView, as: LV
        def go(s, x), do: LV.stream_insert(s, :songs, x)
      end
      """

      assert stream_diffs(source) ==
               [{"LV.stream_insert(s, :songs, x)", "LV.stream_delete(s, :songs, x)"}]
    end

    test "a piped stream_insert(:songs, x) is the 3-arg form and swaps" do
      assert stream_diffs(live("  def go(s, x), do: s |> stream_insert(:songs, x)")) ==
               [{"stream_insert(:songs, x)", "stream_delete(:songs, x)"}]
    end

    test "stream_insert/4 is never swapped to a delete (no stream_delete/4)" do
      source = live("  def go(s, x), do: stream_insert(s, :s, x, at: 0, limit: 5)")

      refute Enum.any?(stream_diffs(source), fn {_original, mutated} ->
               mutated =~ "stream_delete"
             end)
    end
  end

  describe "the at: boundary swap (stream_insert/4)" do
    test "at: 0 (prepend) becomes at: -1 (append)" do
      assert stream_diffs(live("  def go(s, x), do: stream_insert(s, :songs, x, at: 0)")) ==
               [{"stream_insert(s, :songs, x, at: 0)", "stream_insert(s, :songs, x, at: -1)"}]
    end

    test "at: -1 (append, the default) becomes at: 0 (prepend)" do
      assert stream_diffs(live("  def go(s, x), do: stream_insert(s, :songs, x, at: -1)")) ==
               [{"stream_insert(s, :songs, x, at: -1)", "stream_insert(s, :songs, x, at: 0)"}]
    end

    test "a piped stream_insert(:songs, x, at: 0) is effective arity 4 and swaps its at:" do
      assert stream_diffs(live("  def go(s, x), do: s |> stream_insert(:songs, x, at: 0)")) ==
               [{"stream_insert(:songs, x, at: 0)", "stream_insert(:songs, x, at: -1)"}]
    end

    test "an explicitly bracketed [at: 0] swaps too" do
      assert stream_diffs(live("  def go(s, x), do: stream_insert(s, :songs, x, [at: 0])")) ==
               [{"stream_insert(s, :songs, x, at: 0)", "stream_insert(s, :songs, x, at: -1)"}]
    end

    test "sibling options ride along untouched" do
      body = "  def go(s, x), do: stream_insert(s, :songs, x, at: 0, limit: 10)"

      assert {"stream_insert(s, :songs, x, at: 0, limit: 10)",
              "stream_insert(s, :songs, x, at: -1, limit: 10)"} in stream_diffs(live(body))
    end

    test "any other at: value is left to core's IntegerLiteral" do
      assert stream_diffs(live("  def go(s, x), do: stream_insert(s, :songs, x, at: 2)")) == []
      assert stream_diffs(live("  def go(s, x, i), do: stream_insert(s, :songs, x, at: i)")) == []
    end

    test "stream/4's at: is not swapped (the boundary signal lives on the per-item insert)" do
      assert stream_diffs(live("  def go(s, xs), do: stream(s, :songs, xs, at: 0)")) == []
    end
  end

  describe "the limit: drop (stream/4 and stream_insert/4)" do
    test "a sole limit: takes the whole options argument with it" do
      assert stream_diffs(live("  def go(s, xs), do: stream(s, :songs, xs, limit: 10)")) ==
               [{"stream(s, :songs, xs, limit: 10)", "stream(s, :songs, xs)"}]
    end

    test "sibling options survive the drop" do
      body = "  def go(s, xs), do: stream(s, :songs, xs, reset: true, limit: 10)"

      assert stream_diffs(live(body)) ==
               [
                 {"stream(s, :songs, xs, reset: true, limit: 10)",
                  "stream(s, :songs, xs, reset: true)"}
               ]
    end

    test "stream_insert/4's limit: drops too, keeping its at:" do
      body = "  def go(s, x), do: stream_insert(s, :songs, x, at: 0, limit: 10)"

      assert {"stream_insert(s, :songs, x, at: 0, limit: 10)",
              "stream_insert(s, :songs, x, at: 0)"} in stream_diffs(live(body))
    end

    test "a piped stream(:songs, xs, limit: 10) drops to the option-less stage" do
      assert stream_diffs(live("  def go(s, xs), do: s |> stream(:songs, xs, limit: 10)")) ==
               [{"stream(:songs, xs, limit: 10)", "stream(:songs, xs)"}]
    end

    test "reset: is never dropped — core's boolean flip to `reset: false` already owns it" do
      assert stream_diffs(live("  def go(s, xs), do: stream(s, :songs, xs, reset: true)")) == []
    end

    test "update_only: is never dropped either (the same boolean-ownership reasoning)" do
      body = "  def go(s, x), do: stream_insert(s, :songs, x, update_only: true)"
      assert stream_diffs(live(body)) == []
    end
  end

  describe "overlap with core's IntegerLiteral (the covering-swap contract)" do
    test "the at: swap prunes core's integer leaves at the at: value" do
      source = live("  def go(s, x), do: stream_insert(s, :songs, x, at: 0)")
      all = diffs(source, [Mutare.Mutators.IntegerLiteral, StreamMut])

      # The single-node substitution is a covering rewrite, so `Mutare.Transform.Overlap`
      # drops the redundant `0 → 1` / `0 → -1` leaves; this family's swap is the one mutant.
      assert all == [
               {:lv_stream, "stream_insert(s, :songs, x, at: 0)",
                "stream_insert(s, :songs, x, at: -1)"}
             ]
    end

    test "control: without this family, core's integer leaves do fire at that node" do
      source = live("  def go(s, x), do: stream_insert(s, :songs, x, at: 0)")

      assert diffs(source, [Mutare.Mutators.IntegerLiteral]) ==
               [{:integer, "0", "1"}, {:integer, "0", "-1"}]
    end

    test "the limit: value keeps core's integer boundary mutants (a different question)" do
      source = live("  def go(s, xs), do: stream(s, :songs, xs, limit: 10)")

      families =
        source |> diffs([Mutare.Mutators.IntegerLiteral, StreamMut]) |> Enum.map(&elem(&1, 0))

      assert :integer in families
      assert :lv_stream in families
    end
  end

  describe "variant labels (# mutare:ignore[lv_stream:<kind>])" do
    test "the declared vocabulary" do
      assert StreamMut.variants() == ["swap", "at", "limit"]
    end

    test "a qualified directive suppresses one kind and leaves the others live" do
      source =
        live(
          "  def go(s, x), do: stream_insert(s, :songs, x, at: 0, limit: 10) # mutare:ignore[lv_stream:at]"
        )

      result = Mutare.transform_string(source, mutators: [StreamMut])

      assert Enum.map(result.mutants, &{&1.variant, &1.ignored}) ==
               [{["at"], true}, {["limit"], false}]
    end
  end

  describe "scope — unrelated calls" do
    test "a non-stream Phoenix.LiveView call is untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_patch(s, to: \"/x\")\nend\n"

      assert stream_diffs(source) == []
    end

    test "a non-keyword options argument (a variable) offers nothing" do
      assert stream_diffs(live("  def go(s, x, o), do: stream_insert(s, :songs, x, o)")) == []
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified stream_insert/3 swaps to stream_delete" do
      assert node_mutations("Phoenix.LiveView.stream_insert(s, :k, x)", StreamMut) == [
               "Phoenix.LiveView.stream_delete(s, :k, x)"
             ]
    end

    test "qualified stream_insert/4 yields its option mutants" do
      assert node_mutations(
               "Phoenix.LiveView.stream_insert(s, :k, x, at: 0, limit: 5)",
               StreamMut
             ) ==
               [
                 "Phoenix.LiveView.stream_insert(s, :k, x, at: -1, limit: 5)",
                 "Phoenix.LiveView.stream_insert(s, :k, x, at: 0)"
               ]
    end

    test "node-local mutate/1 never fires (it has no pipe context)" do
      node = Mutare.AST.parse!("Phoenix.LiveView.stream_insert(s, :k, x)")
      assert StreamMut.mutate(node) == :skip
    end
  end

  test "every embedded mutant compiles" do
    source = """
    defmodule StreamCompileDemo do
      import Phoenix.LiveView

      def fill(socket, songs) do
        socket
        |> stream(:songs, songs, reset: true, limit: 10)
        |> stream(:albums, [], limit: -5)
      end

      def add(socket, song) do
        socket
        |> stream_insert(:songs, song)
        |> stream_insert(:songs, song, at: 0)
        |> stream_insert(:songs, song, at: -1, limit: 10)
        |> stream_delete(:songs, song)
      end
    end
    """

    assert_metamutant_compiles(source, [StreamMut])
  end
end
