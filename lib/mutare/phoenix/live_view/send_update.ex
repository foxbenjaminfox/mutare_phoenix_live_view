defmodule Mutare.Phoenix.LiveView.SendUpdate do
  @moduledoc """
  `:lv_send_update` — mutates a `Phoenix.LiveView` component-update call, the message that tells
  a child `Phoenix.LiveComponent` to re-render with new assigns. Two kinds, each a variant label:

  **`remove`** drops the update ("does the update matter?"):

      send_update(Cart, id: "cart", count: 3)            ->  :ok
      send_update(pid, Cart, id: "cart", count: 3)       ->  :ok
      send_update_after(Cart, [id: "cart"], 1_000)       ->  :erlang.make_ref()
      send_update_after(pid, Cart, [id: "cart"], 1_000)  ->  :erlang.make_ref()

  **`immediate`** keeps the update but drops the *delay* ("does the timing matter?"):

      send_update_after(Cart, [id: "cart"], 1_000)       ->  send_update(Cart, id: "cart")
                                                             :erlang.make_ref()

  A `remove` survivor means no test asserts the child component was told to update — that it
  re-renders with the new assigns (`Phoenix.LiveViewTest.render_component/2`, or asserting the
  live render reflects the change). It is the `LiveComponent` sibling of `:lv_event`'s dropped
  client push: same "forgot to fire a side effect" removal, aimed at the server→component
  channel rather than the server→client one. An `immediate` survivor means no test depends on
  the update being *deferred* — the delay could be deleted (or garbled) without a failure.
  Suppress one kind with `# mutare:ignore[lv_send_update:remove]` / `[lv_send_update:immediate]`,
  or the whole family with `# mutare:ignore[lv_send_update]`.

  Unlike `push_event` (socket-in, socket-out), `send_update`/`send_update_after` are
  fire-and-forget side effects that never return the socket — so both kinds collapse the whole
  call to a happy-path return (not to an argument), and the two calls differ. `send_update`'s
  return is undocumented (under the hood, the raw `send/2` echo), so the conventional `:ok`
  stands in; `send_update_after` documents its return — the scheduled timer's `reference()` —
  so its no-ops end in a fresh `:erlang.make_ref()`. The `immediate` mutant is a two-expression
  block for the same reason: `send_update/2,3` alone would change the return type, while
  `(send_update(...); :erlang.make_ref())` fires the update now *and* keeps the documented ref
  type. Matching that type keeps both mutants clean no-ops even at the rare site that captures
  the ref to `Process.cancel_timer/1` it later — cancelling an unknown ref returns `false`,
  where a `:ok` there would raise (an uninformative crash-kill this package exists to avoid).

  The delay argument itself is marked with the shared `:timeout` label
  (`c:Mutare.Mutator.argument_marks/1`), so core's `IntegerLiteral`/`AtomLiteral` leave the
  duration literal alone — the `immediate` mutant owns the timing question, and a `1_000 → 1_001`
  off-by-one there is the near-unkillable noise those families' own timeout table exists to
  avoid.

  Because no socket flows through, these calls are never idiomatically piped (a direct pipe
  would feed the module/pid slot), so a piped occurrence is left alone rather than given a
  non-faithful `Function.identity()` pass-through. Only the real arities fire — `send_update/2,3`
  and `send_update_after/3,4` — so a name-matched call of any other arity (reachable only by an
  explicit qualifier) is left alone, keeping every metamutant compiling.

  Matches direct (`Phoenix.LiveView.send_update(...)`), aliased, and bare-imported
  (`use`-injected) calls. Like `:lv_event`, this family has a high equivalent-mutant rate in
  suites that never assert a component re-rendered — drop it from your preset if that is noisy.
  """
  @behaviour Mutare.Mutator

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation

  # The `rebuild` closure `Calls.resolved_call_to/3` hands back: re-emits the call in its
  # written form with a new function name and argument list.
  @typep rebuild :: (atom(), [Macro.t()] -> Macro.t())

  @impl Mutare.Mutator
  @spec name() :: :lv_send_update
  def name, do: :lv_send_update

  # Never fires node-locally: recognising the call needs its effective arity, and the piped
  # form is deliberately skipped — both need the pipe context only `mutate/2` carries.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The `%{pipe_mode: …}` head is total over every context the engine threads here, so there is
  # no catch-all clause — see `Navigation.mutate/2` for why a fallback would be dead code.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call_to(node, Phoenix.LiveView) do
      {:ok, fun, args, rebuild} -> mutations(fun, args, pipe_mode, rebuild)
      :error -> :skip
    end
  end

  # Variant vocabulary for `# mutare:ignore[lv_send_update:<label>]`: `remove` = the dropped
  # update, `immediate` = the dropped delay. Tagged at production below.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(remove immediate)

  # The delay of `send_update_after/3,4` (its last argument) is a duration literal like the ones
  # core's `IntegerLiteral` timeout table pins for `Process.send_after`/`GenServer.call`: an
  # off-by-one there is a near-unkillable equivalent mutant, and this family's `immediate` swap
  # already owns the "does the timing matter?" question wholesale. The shared `:timeout` label is
  # what `IntegerLiteral` (and `AtomLiteral`, for `:infinity`) react to.
  @impl Mutare.Mutator
  @spec argument_marks(term()) :: [{module(), atom(), arity(), [non_neg_integer()], atom()}]
  def argument_marks(_config) do
    [
      {Phoenix.LiveView, :send_update_after, 3, [2], :timeout},
      {Phoenix.LiveView, :send_update_after, 4, [3], :timeout}
    ]
  end

  # A piped call is left alone: it returns `:ok` / a ref, not its left side, so
  # `Function.identity()` would change the value — and a direct pipe into the module/pid slot is
  # never idiomatic anyway.
  @spec mutations(atom(), [Macro.t()], Mutator.pipe_mode(), rebuild()) :: :skip | [Mutation.t()]
  defp mutations(_fun, _args, :piped, _rebuild), do: :skip

  # `send_update/2,3` (`(module, assigns)` / `(pid, module, assigns)`): removal collapses the
  # *statement* to the stand-in `:ok` return. The arity pin keeps a wrong-arity qualified call
  # (the only way a non-matching arity reaches here) unmutated, so every metamutant compiles.
  defp mutations(:send_update, args, pipe_mode, _rebuild) do
    if Mutator.effective_arity(args, pipe_mode) in [2, 3],
      do: [Mutation.tagged(AST.literal(:ok), "remove")],
      else: :skip
  end

  # `send_update_after/3,4` (the same two shapes plus the trailing delay): removal collapses to
  # a fresh reference, and the `immediate` kind reschedules the update for *now* — both arities
  # translate cleanly to the `send_update` sibling by dropping the trailing delay.
  defp mutations(:send_update_after, args, pipe_mode, rebuild) do
    if Mutator.effective_arity(args, pipe_mode) in [3, 4],
      do: [
        Mutation.tagged(ref_call(), "remove"),
        Mutation.tagged(immediate(args, rebuild), "immediate")
      ],
      else: :skip
  end

  defp mutations(_fun, _args, _pipe_mode, _rebuild), do: :skip

  # The `immediate` mutant: `send_update(...same args minus the delay...)` followed by a fresh
  # reference, so the value the expression yields keeps `send_update_after`'s documented
  # `reference()` type (a bare `send_update` call would return its `:ok`-ish echo instead).
  # `rebuild` keeps the written form — a bare `use`-imported call stays bare (`send_update/2,3`
  # is imported from the same whole-module import), a qualified/aliased one keeps its qualifier.
  @spec immediate([Macro.t()], rebuild()) :: Macro.t()
  defp immediate(args, rebuild),
    do: {:__block__, [], [rebuild.(:send_update, Enum.drop(args, -1)), ref_call()]}

  # `:erlang.make_ref()` — the `:erlang`-qualified BIF is never rewritten by alias resolution
  # (the `:lv_event` `Elixir.Function.identity()` trick), so the no-op always names the real one.
  @spec ref_call() :: Macro.t()
  defp ref_call, do: {{:., [], [:erlang, :make_ref]}, [], []}
end
