defmodule Mutare.Phoenix.LiveView.SendUpdate do
  @moduledoc """
  `:lv_send_update` — removes a `Phoenix.LiveView` component-update call, the message that tells
  a child `Phoenix.LiveComponent` to re-render with new assigns:

      send_update(Cart, id: "cart", count: 3)            ->  :ok
      send_update(pid, Cart, id: "cart", count: 3)       ->  :ok
      send_update_after(Cart, [id: "cart"], 1_000)       ->  :erlang.make_ref()
      send_update_after(pid, Cart, [id: "cart"], 1_000)  ->  :erlang.make_ref()

  A survivor means no test asserts the child component was told to update — that it re-renders
  with the new assigns (`Phoenix.LiveViewTest.render_component/2`, or asserting the live render
  reflects the change). It is the `LiveComponent` sibling of `:lv_event`'s dropped client push:
  same "forgot to fire a side effect" removal, aimed at the server→component channel rather than
  the server→client one.

  Unlike `push_event` (socket-in, socket-out), `send_update`/`send_update_after` are
  fire-and-forget side effects that never return the socket — so removal collapses the whole
  call to a happy-path return (not to an argument), and the two differ. `send_update`'s return
  is undocumented (under the hood, the raw `send/2` echo), so the conventional `:ok` stands in;
  `send_update_after` documents its return — the scheduled timer's `reference()` — so its no-op
  is a fresh `:erlang.make_ref()`. Matching the documented ref type keeps the mutant a clean
  no-op even at the rare site that captures the ref to `Process.cancel_timer/1` it later —
  cancelling an unknown ref returns `false`, where a `:ok` there would raise (an uninformative
  crash-kill this package exists to avoid).

  Because no socket flows through, these calls are never idiomatically piped (a direct pipe
  would feed the module/pid slot), so a piped occurrence is left alone rather than given a
  non-faithful `Function.identity()` pass-through. Only the real arities fire — `send_update/2,3`
  and `send_update_after/3,4` — so a name-matched call of any other arity (reachable only by an
  explicit qualifier) is left alone, keeping every metamutant compiling.

  Matches direct (`Phoenix.LiveView.send_update(...)`), aliased, and bare-imported
  (`use`-injected) calls. Silence a site with `# mutare:ignore[lv_send_update]`. Like
  `:lv_event`, this family has a high equivalent-mutant rate in suites that never assert a
  component re-rendered — drop it from your preset if that is noisy.
  """
  @behaviour Mutare.Mutator

  alias Mutare.AST
  alias Mutare.Calls
  alias Mutare.Mutator

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
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Macro.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call_to(node, Phoenix.LiveView) do
      {:ok, fun, args, _rebuild} -> removed_call(fun, args, pipe_mode)
      :error -> :skip
    end
  end

  # Collapse a component-update *statement* to the value its call returns. A piped call is left
  # alone: it returns `:ok` / a ref, not its left side, so `Function.identity()` would change the
  # value — and a direct pipe into the module/pid slot is never idiomatic anyway.
  @spec removed_call(atom(), [Macro.t()], Mutator.pipe_mode()) :: :skip | [Macro.t()]
  defp removed_call(_fun, _args, :piped), do: :skip

  defp removed_call(fun, args, pipe_mode) do
    if valid_arity?(fun, Mutator.effective_arity(args, pipe_mode)),
      do: [removal(fun)],
      else: :skip
  end

  # Each call's happy-path return, so the mutant differs from the original only by the dropped
  # side effect — not by usable type. `send_update`'s return is undocumented (`:ok` stands in);
  # `send_update_after` schedules a timer and returns its `reference()`, so its no-op yields a
  # fresh reference no live timer backs (a captured ref then `Process.cancel_timer/1`s cleanly
  # to `false`, never crashing).
  #
  # Deliberately unspecced: the two function heads make the success-typing domain
  # `:send_update | :send_update_after`, but the lone caller reaches here holding a plain
  # `atom()` (the `valid_arity?/2` guard narrows it only at runtime). A precise spec would make
  # that call break the contract; a widened `atom()` spec would over-claim the heads. Inference
  # lands it correctly, so leave it.
  defp removal(:send_update), do: AST.literal(:ok)
  defp removal(:send_update_after), do: ref_call()

  # `:erlang.make_ref()` — the `:erlang`-qualified BIF is never rewritten by alias resolution
  # (the `:lv_event` `Elixir.Function.identity()` trick), so the no-op always names the real one.
  @spec ref_call() :: Macro.t()
  defp ref_call, do: {{:., [], [:erlang, :make_ref]}, [], []}

  # `send_update/2,3` (`(module, assigns)` / `(pid, module, assigns)`) and `send_update_after/3,4`
  # (the same two plus the trailing delay) — the arities each component-update call really has.
  # Pinning them keeps a wrong-arity qualified call (the only way a non-matching arity reaches
  # here) from being mutated, and keeps every metamutant compiling.
  @spec valid_arity?(atom(), non_neg_integer()) :: boolean()
  defp valid_arity?(:send_update, arity), do: arity in [2, 3]
  defp valid_arity?(:send_update_after, arity), do: arity in [3, 4]
  defp valid_arity?(_fun, _arity), do: false
end
