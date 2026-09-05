defmodule Mutare.Phoenix.LiveView.Hook do
  @moduledoc """
  `:lv_hook` — removes a `Phoenix.LiveView` lifecycle-hook management call, collapsing it to
  the socket it would have returned:

      attach_hook(socket, :log, :handle_event, &log/3)  ->  socket
      detach_hook(socket, :log, :handle_event)          ->  socket
      socket |> attach_hook(:log, :handle_event, &log/3)  ->  Elixir.Function.identity()

  Both directions of the hook lifecycle are one family with two variant labels: `attach`
  ("no test depends on this hook running" — the hook never fires) and `detach` ("no test
  depends on this hook *stopping*" — the hook keeps running). Suppress one kind with
  `# mutare:ignore[lv_hook:attach]` / `[lv_hook:detach]`, or the whole family with
  `# mutare:ignore[lv_hook]`.

  Only the attachment is this family's seam. The `:cont`/`:halt` decision *inside* a hook
  function (and in `on_mount/4`) belongs to Mutare's built-in `:convention` family, which
  swaps those atoms wherever they appear — enabling both families mutates the two axes
  independently.

  Only the real arities fire — `attach_hook/4` and `detach_hook/3` — so a name-matched call
  of any other arity (reachable only by an explicit qualifier) is left alone, keeping every
  metamutant compiling. Piped calls are removed with the `Elixir.Function.identity()` no-op
  stage (the `:lv_event` trick — the `:Elixir`-led alias is never rewritten by alias
  resolution, so the no-op always names the real `Function.identity/1`).

  The hook *name* and *stage* arguments are structural identifiers, not computed values —
  perturbing `:handle_event` raises inside `attach_hook` (an uninformative crash-kill), and a
  renamed hook still runs (a near-unkillable equivalent). This family therefore routes both
  positions `:raw` (`Mutare.CallRouting`), so no core family — `AtomLiteral`, `StringLiteral`,
  `ConventionAtom`, … — mutates them or anything inside them.

  Matches direct (`Phoenix.LiveView.attach_hook(...)`), aliased, and bare-imported
  (`use`-injected) calls.
  """
  @behaviour Mutare.Mutator
  @behaviour Mutare.CallRouting

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.Mutator
  alias Mutare.Mutator.Mutation

  @impl Mutare.Mutator
  @spec name() :: :lv_hook
  def name, do: :lv_hook

  # Never fires node-locally: whether removal returns the first arg (non-piped) or
  # `Function.identity()` (piped) depends on pipe context, unknowable from the node.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The `%{pipe_mode: …}` head is total over every context the engine threads here, so there is
  # no catch-all clause — see `Navigation.mutate/2` for why a fallback would be dead code.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Mutation.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call_to(node, Phoenix.LiveView, [:attach_hook, :detach_hook]) do
      {:ok, fun, args, _rebuild} -> removed_call(fun, args, pipe_mode)
      :error -> :skip
    end
  end

  # Variant vocabulary for `# mutare:ignore[lv_hook:<label>]`: which end of the hook lifecycle
  # was removed. Tagged at production in `removed_call/3`.
  @impl Mutare.Mutator
  @spec variants() :: [String.t()]
  def variants, do: ~w(attach detach)

  # The hook name (effective index 1) and stage (index 2) are structural identifiers — a label
  # the code detaches by and a stage atom `attach_hook` validates — not values the program
  # computes with. Route them `:raw` so no core family (`AtomLiteral` on `:handle_event`,
  # `StringLiteral` on a string name) ever mints the crash-kill / near-equivalent mutants there.
  # The socket (index 0) and the hook function (index 3) stay ordinary expressions; the routed
  # call is still offered whole to `mutate/2`, which is how this family removes it.
  @impl Mutare.CallRouting
  @spec call_routes() :: [Mutare.CallRouting.route()]
  def call_routes do
    [
      {Phoenix.LiveView, :attach_hook, 4, [:expression, :raw, :raw, :expression]},
      {Phoenix.LiveView, :detach_hook, 3, [:expression, :raw, :raw]}
    ]
  end

  # `attach_hook/4` (`(socket, name, stage, fun)`) and `detach_hook/3` (`(socket, name, stage)`)
  # are the only real arities. Pinning them keeps a wrong-arity qualified call (the only way a
  # non-matching arity reaches here) from being mutated, and keeps every metamutant compiling.
  # No catch-all heads: `mutate/2` filters to exactly these two names.
  @spec removed_call(atom(), [Macro.t()], Mutator.pipe_mode()) :: :skip | [Mutation.t()]
  defp removed_call(fun, args, pipe_mode) do
    if valid_arity?(fun, Mutator.effective_arity(args, pipe_mode)),
      do: [Mutation.tagged(removal(args, pipe_mode), label(fun))],
      else: :skip
  end

  @spec valid_arity?(atom(), non_neg_integer()) :: boolean()
  defp valid_arity?(:attach_hook, arity), do: arity == 4
  defp valid_arity?(:detach_hook, arity), do: arity == 3

  @spec label(atom()) :: String.t()
  defp label(:attach_hook), do: "attach"
  defp label(:detach_hook), do: "detach"

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first
  # argument (the socket). The arity guard guarantees a non-piped call has that argument,
  # so the `:unpiped` clause only ever sees the non-empty list its spec promises.
  @spec removal([Macro.t(), ...], Mutator.pipe_mode()) :: Macro.t()
  defp removal(_args, :piped), do: AST.absolute_call([:Function], :identity, [])
  defp removal([socket | _rest], :unpiped), do: socket
end
