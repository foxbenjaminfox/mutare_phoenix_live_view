defmodule Mutare.Phoenix.LiveView.StreamTest do
  @moduledoc """
  `:lv_stream` — inverts `stream_insert` ↔ `stream_delete`.
  Pipe-aware (`mutate/2`): the swap is emitted only for the 3-arg form both functions share,
  because `stream_delete` has no arity-4 — so a `stream_insert/4` (with `opts`) is left alone.
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
  end

  describe "pipe awareness (effective arity recovers the off-by-one)" do
    test "a piped stream_insert(:songs, x) is the 3-arg form and swaps" do
      assert stream_diffs(live("  def go(s, x), do: s |> stream_insert(:songs, x)")) ==
               [{"stream_insert(:songs, x)", "stream_delete(:songs, x)"}]
    end

    test "a piped stream_insert(:songs, x, at: 0) is effective arity 4 — left alone" do
      assert stream_diffs(live("  def go(s, x), do: s |> stream_insert(:songs, x, at: 0)")) == []
    end
  end

  describe "scope — the arity-4 guard and unrelated calls" do
    test "stream_insert/4 (with opts) is NOT swapped (no stream_delete/4)" do
      source =
        "defmodule L do\n  def go(s, x), do: Phoenix.LiveView.stream_insert(s, :s, x, at: 0)\nend\n"

      assert stream_diffs(source) == []
    end

    test "a non-stream Phoenix.LiveView call is untouched" do
      source =
        "defmodule L do\n  def go(s), do: Phoenix.LiveView.push_patch(s, to: \"/x\")\nend\n"

      assert stream_diffs(source) == []
    end
  end

  describe "pure-AST node path (mutations/3)" do
    test "qualified stream_insert/3 swaps to stream_delete" do
      assert node_mutations("Phoenix.LiveView.stream_insert(s, :k, x)", StreamMut) == [
               "Phoenix.LiveView.stream_delete(s, :k, x)"
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

      def add(socket, song) do
        socket
        |> stream_insert(:songs, song)
        |> stream_delete(:songs, song)
      end
    end
    """

    assert_metamutant_compiles(source, [StreamMut])
  end
end
