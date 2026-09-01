defmodule Mutare.Phoenix.LiveView.Stream do
  @moduledoc """
  `:lv_stream` — mutates `Phoenix.LiveView` stream operations. Three kinds, each a variant
  label:

  **`swap`** inverts an operation for its opposite:

      stream_insert(socket, name, item)  <->  stream_delete(socket, name, item)

  Inserting where the code meant to delete (or vice versa) leaves the wrong rows in the
  `phx-update="stream"` container. A test that asserts a stream's *contents* after the event
  kills it; one that only checks the event returned lets it survive. Only the 3-argument form
  is swapped — `stream_insert` also exists at arity 4 but `stream_delete` does not, so a
  `stream_insert/4` gets the option mutations below instead, keeping every mutant compiling.

  **`at`** swaps the `at:` option between its two boundary positions on `stream_insert/4`:

      stream_insert(socket, name, item, at: 0)   <->  stream_insert(socket, name, item, at: -1)

  Prepend vs append (`-1`, the default, appends). Tests overwhelmingly assert an item is
  *present*, rarely *where* — a survivor means nothing pins the insertion position. Only the
  two boundary literals swap; any other `at:` value (a computed index, `at: 2`) is left to
  core's `IntegerLiteral`. The swap substitutes exactly the `at:` value node, so core's
  `Mutare.Transform.Overlap` recognises it as covering and prunes `IntegerLiteral`'s redundant
  leaf mutants (`0 → 1`, `0 → -1`) at that node — this family's position swap is the one
  informative mutant there.

  **`limit`** drops the `limit:` entry from `stream/4` and `stream_insert/4`:

      stream(socket, name, items, limit: 10)     ->  stream(socket, name, items)
      stream_insert(socket, name, item, at: 0, limit: 10)
                                                 ->  stream_insert(socket, name, item, at: 0)

  The unbounded stream is a valid-but-wrong program: without the limit the client container
  grows without pruning. A survivor means no test fills past the limit and asserts the pruned
  contents. (Presence-drop of the *entry* is not core-owned; the limit's numeric *value* stays
  `IntegerLiteral`'s — an off-by-one on the boundary is a genuinely different question.)

  No `reset:` mutation, deliberately: dropping `reset: true` is equivalent to core
  `BooleanLiteral`'s `true → false` flip on the same literal (`false` is the default), so a
  drop here would double-report the same mutant — an ownership violation. The same holds for
  `stream_insert/4`'s boolean `update_only:` option.

  Suppress one kind with `# mutare:ignore[lv_stream:swap]` / `[lv_stream:at]` /
  `[lv_stream:limit]`, or the whole family with `# mutare:ignore[lv_stream]`. Pipe forms
  (`socket |> stream_insert(:songs, song)`) count toward every arity gate.

  Matches direct, aliased, and bare-imported (`use`-injected) calls. This family has a high
  equivalent-mutant rate in apps that don't assert stream contents — drop it from your preset
  if that is noisy.
  """
  @behaviour Mutare.Mutator

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation

  # The `rebuild` closure `Calls.resolved_call_to/3` hands back: re-emits the call in its
  # written form with a new function name and argument list.
  @typep rebuild :: (atom(), [Macro.t()] -> Macro.t())

  # Rebuilds an options argument from its (possibly changed) keyword entries, preserving the
  # written shape — bare trailing keywords stay bare, a bracketed list keeps its wrapper node.
  @typep rewrap :: ([Macro.t()] -> Macro.t())

  @impl Mutare.Mutator
  @spec name() :: :lv_stream
  def name, do: :lv_stream

  # Never fires node-locally: every gate below depends on effective arity, which isn't
  # knowable without pipe context.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The `%{pipe_mode: …}` head is total over every context the engine threads here, so there is
  # no catch-all clause — see `Navigation.mutate/2` for why a fallback would be dead code.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call_to(node, Phoenix.LiveView) do
      {:ok, fun, args, rebuild} -> stream_mutations(fun, args, pipe_mode, rebuild)
      :error -> :skip
    end
  end

  # Variant vocabulary for `# mutare:ignore[lv_stream:<label>]`: `swap` = insert↔delete,
  # `at` = the prepend↔append boundary swap, `limit` = the dropped `limit:` entry. Tagged at
  # production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(swap at limit)

  # `stream_insert` swaps to `stream_delete` at the 3-arg form both functions share; the 4-arg
  # form (with `opts` — `stream_delete` has no arity-4 twin) gets the option mutations instead.
  @spec stream_mutations(atom(), [Macro.t()], Mutator.pipe_mode(), rebuild()) ::
          :skip | [Mutation.t()]
  defp stream_mutations(:stream_insert, args, pipe_mode, rebuild) do
    case Mutator.effective_arity(args, pipe_mode) do
      3 -> [Mutation.tagged(rebuild.(:stream_delete, args), "swap")]
      4 -> option_mutations(:stream_insert, args, rebuild, at: true)
      _ -> :skip
    end
  end

  defp stream_mutations(:stream_delete, args, pipe_mode, rebuild) do
    if Mutator.effective_arity(args, pipe_mode) == 3,
      do: [Mutation.tagged(rebuild.(:stream_insert, args), "swap")],
      else: :skip
  end

  # `stream/4` takes `at:` too, but its `at:` positions a whole initial batch — the boundary
  # swap's signal lives on the per-item `stream_insert/4`, so only the `limit:` drop fires here.
  defp stream_mutations(:stream, args, pipe_mode, rebuild) do
    if Mutator.effective_arity(args, pipe_mode) == 4,
      do: option_mutations(:stream, args, rebuild, at: false),
      else: :skip
  end

  defp stream_mutations(_fun, _args, _pipe_mode, _rebuild), do: :skip

  # The option mutations of a 4-effective-arity call, read off its written options argument —
  # always the last *visible* one (a piped receiver never holds the opts). A non-keyword options
  # argument (a variable, a map) offers nothing.
  @spec option_mutations(atom(), [Macro.t()], rebuild(), at: boolean()) :: :skip | [Mutation.t()]
  defp option_mutations(fun, args, rebuild, at: at?) do
    case keyword_opts(List.last(args)) do
      {:ok, entries, rewrap} ->
        at_swaps = if at?, do: at_swap(fun, args, rebuild, entries, rewrap), else: []
        wrap_skip(at_swaps ++ limit_drop(fun, args, rebuild, entries, rewrap))

      :error ->
        :skip
    end
  end

  @spec wrap_skip([Mutation.t()]) :: :skip | [Mutation.t()]
  defp wrap_skip([]), do: :skip
  defp wrap_skip(mutations), do: mutations

  # An options argument as `{entries, rewrap}`: bare trailing keywords are the entry list
  # itself; an explicitly bracketed `[...]` arrives Sourceror-wrapped, and `rewrap` restores
  # the wrapper so the mutant renders in the written shape.
  @spec keyword_opts(Macro.t()) :: {:ok, [Macro.t()], rewrap()} | :error
  defp keyword_opts({:__block__, meta, [entries]}) when is_list(entries),
    do: {:ok, entries, fn new -> {:__block__, meta, [new]} end}

  defp keyword_opts(entries) when is_list(entries), do: {:ok, entries, fn new -> new end}
  defp keyword_opts(_node), do: :error

  # `at: 0 ↔ at: -1`, substituting exactly the value node (fresh literal via `AST.literal/1`,
  # every other node reused verbatim) — the single-node diff is what lets core's Overlap pass
  # recognise the rewrite as covering and drop `IntegerLiteral`'s redundant leaves there.
  @spec at_swap(atom(), [Macro.t()], rebuild(), [Macro.t()], rewrap()) :: [Mutation.t()]
  defp at_swap(fun, args, rebuild, entries, rewrap) do
    case find_opt(entries, :at) do
      {:ok, value} ->
        case at_replacement(value) do
          {:ok, swapped} ->
            entries = replace_opt(entries, :at, swapped)
            [Mutation.tagged(rebuild_opts(fun, args, rebuild, rewrap.(entries)), "at")]

          :error ->
            []
        end

      :error ->
        []
    end
  end

  # Only the two boundary literals swap. `-1` is Sourceror's unary-minus shape (`{:-, _, [1]}`),
  # matched as such; any other value is a genuine index and stays `IntegerLiteral`'s.
  @spec at_replacement(Macro.t()) :: {:ok, Macro.t()} | :error
  defp at_replacement({:-, _meta, [inner]}) do
    case AST.literal_value(inner) do
      {:ok, 1} -> {:ok, AST.literal(0)}
      _other -> :error
    end
  end

  defp at_replacement(value) do
    case AST.literal_value(value) do
      {:ok, 0} -> {:ok, AST.literal(-1)}
      _other -> :error
    end
  end

  # Drop the `limit:` entry. When it was the sole option the whole argument goes with it — both
  # hosts exist at arity 3 (`opts \\ []`), so the shorter call always compiles.
  @spec limit_drop(atom(), [Macro.t()], rebuild(), [Macro.t()], rewrap()) :: [Mutation.t()]
  defp limit_drop(fun, args, rebuild, entries, rewrap) do
    if find_opt(entries, :limit) == :error do
      []
    else
      node =
        case reject_opt(entries, :limit) do
          [] -> rebuild.(fun, Enum.drop(args, -1))
          remaining -> rebuild_opts(fun, args, rebuild, rewrap.(remaining))
        end

      [Mutation.tagged(node, "limit")]
    end
  end

  # Re-emit the call with its options argument (the last visible one) replaced.
  @spec rebuild_opts(atom(), [Macro.t()], rebuild(), Macro.t()) :: Macro.t()
  defp rebuild_opts(fun, args, rebuild, opts), do: rebuild.(fun, List.replace_at(args, -1, opts))

  @spec find_opt([Macro.t()], atom()) :: {:ok, Macro.t()} | :error
  defp find_opt(entries, key) do
    Enum.find_value(entries, :error, fn
      {k, value} -> if AST.key_atom(k) == key, do: {:ok, value}
      _entry -> nil
    end)
  end

  # Replace `key`'s value, keeping the written key node (its `format: :keyword` marker) and
  # every other entry untouched.
  @spec replace_opt([Macro.t()], atom(), Macro.t()) :: [Macro.t()]
  defp replace_opt(entries, key, value) do
    Enum.map(entries, fn
      {k, _v} = entry -> if AST.key_atom(k) == key, do: {k, value}, else: entry
      entry -> entry
    end)
  end

  @spec reject_opt([Macro.t()], atom()) :: [Macro.t()]
  defp reject_opt(entries, key) do
    Enum.reject(entries, fn
      {k, _v} -> AST.key_atom(k) == key
      _entry -> false
    end)
  end
end
