defmodule Mutare.Phoenix.LiveView.Stream do
  @moduledoc """
  `:lv_stream` — swaps a `Phoenix.LiveView` stream operation for its inverse:

      stream_insert(socket, name, item)  <->  stream_delete(socket, name, item)

  Inserting where the code meant to delete (or vice versa) leaves the wrong rows in the
  `phx-update="stream"` container. A test that asserts a stream's *contents* after the event
  kills it; one that only checks the event returned lets it survive.

  Only the 3-argument form is swapped — `stream_insert` also exists at arity 4
  (`stream_insert(socket, name, item, opts)`) but `stream_delete` does not, so a
  `stream_insert/4` is left alone to keep every mutant compiling. Pipe forms
  (`socket |> stream_insert(:songs, song)`) count toward that arity.

  Matches direct, aliased, and bare-imported (`use`-injected) calls. Silence a site with
  `# mutare:ignore[lv_stream]`. This family has a high equivalent-mutant rate in apps that
  don't assert stream contents — drop it from your preset if that is noisy.
  """
  @behaviour Mutare.Mutator

  alias Mutare.Mutator
  alias Mutare.Transform.Calls

  # The `rebuild` closure `Calls.resolved_call/1` hands back: re-emits the call in its
  # written form with a new function name and argument list.
  @typep rebuild :: (atom(), [Macro.t()] -> Macro.t())

  @impl Mutare.Mutator
  @spec name() :: :lv_stream
  def name, do: :lv_stream

  # Never fires node-locally: whether a `stream_insert` is the swappable 3-arg form depends
  # on its effective arity, which isn't knowable without pipe context.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The `%{pipe_mode: …}` head is total over every context the engine threads here, so there is
  # no catch-all clause — see `Navigation.mutate/2` for why a fallback would be dead code.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Macro.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call(node) do
      {[:Phoenix, :LiveView], fun, args, rebuild} -> stream_swaps(fun, args, pipe_mode, rebuild)
      _other -> :skip
    end
  end

  # Swap insert↔delete, but only for the 3-arg form both functions share — `stream_delete`
  # has no arity-4, so a `stream_insert/4` (with an `opts` keyword) is left alone to keep the
  # metamutant compile-safe.
  @spec stream_swaps(atom(), [Macro.t()], Mutator.pipe_mode(), rebuild()) :: :skip | [Macro.t()]
  defp stream_swaps(:stream_insert, args, pipe_mode, rebuild),
    do: swap_when_arity_3(args, pipe_mode, fn -> rebuild.(:stream_delete, args) end)

  defp stream_swaps(:stream_delete, args, pipe_mode, rebuild),
    do: swap_when_arity_3(args, pipe_mode, fn -> rebuild.(:stream_insert, args) end)

  defp stream_swaps(_fun, _args, _pipe_mode, _rebuild), do: :skip

  @spec swap_when_arity_3([Macro.t()], Mutator.pipe_mode(), (-> Macro.t())) :: :skip | [Macro.t()]
  defp swap_when_arity_3(args, pipe_mode, build) do
    if Mutator.effective_arity(args, pipe_mode) == 3, do: [build.()], else: :skip
  end
end
