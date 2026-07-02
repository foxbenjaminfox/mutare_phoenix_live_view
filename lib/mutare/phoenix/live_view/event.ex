defmodule Mutare.Phoenix.LiveView.Event do
  @moduledoc """
  `:lv_event` — removes `Phoenix.LiveView.push_event/3`, the call that ships a server-initiated
  event to the client's `handleEvent` JS hook (`push_event(socket, "highlight", %{id: 1})`):

      push_event(socket, event, payload)     ->  socket
      socket |> push_event(event, payload)   ->  socket

  A survivor means no test asserts the event reaches the client.
  `Phoenix.LiveViewTest.assert_push_event/3` is the assertion that kills it.
  """
  @behaviour Mutare.Mutator

  alias Mutare.Mutator
  alias Mutare.Transform.Calls

  @impl Mutare.Mutator
  @spec name() :: :lv_event
  def name, do: :lv_event

  # Never fires node-locally: whether removal returns the first arg (non-piped) or
  # `Function.identity()` (piped) depends on pipe context, unknowable from the node.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The `%{pipe_mode: …}` head is total over every context the engine threads here, so there is
  # no catch-all clause — see `Navigation.mutate/2` for why a fallback would be dead code.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Macro.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call(node) do
      {[:Phoenix, :LiveView], :push_event, args, _rebuild} -> removed_call(args, pipe_mode)
      _other -> :skip
    end
  end

  # `push_event/3` is the only arity, so removal fires only for the effective-arity-3 form.
  # The guard pins that down — a name-matched call of any other arity (only possible by
  # qualifier, since the bare-import path resolves against the real `/3`) is left alone — so
  # removal always has a first argument to collapse to and never strands a zero-arg call.
  @spec removed_call([Macro.t()], Mutator.pipe_mode()) :: :skip | [Macro.t()]
  defp removed_call(args, pipe_mode) do
    if Mutator.effective_arity(args, pipe_mode) == 3, do: [removal(args, pipe_mode)], else: :skip
  end

  # A piped stage becomes the identity no-op; a non-piped call collapses to its first
  # argument (the socket). The arity-3 guard guarantees a non-piped call has that argument,
  # so the `:unpiped` clause only ever sees the non-empty list its spec promises.
  @spec removal([Macro.t(), ...], Mutator.pipe_mode()) :: Macro.t()
  defp removal(_args, :piped), do: identity_call()
  defp removal([first | _rest], :unpiped), do: first

  # `Elixir.Function.identity()` — the `:Elixir`-led alias is never rewritten by alias
  # resolution, so the no-op always names the real `Function.identity/1`.
  @spec identity_call() :: Macro.t()
  defp identity_call,
    do: {{:., [], [{:__aliases__, [], [:"Elixir", :Function]}, :identity]}, [], []}
end
