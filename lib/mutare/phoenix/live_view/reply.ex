defmodule Mutare.Phoenix.LiveView.Reply do
  @moduledoc """
  `:lv_reply` — drops the optional trailing element of a LiveView callback's return tuple,
  reshaping it into a different but still valid return. Fires in modules that implement
  `@behaviour Phoenix.LiveView` **or** `@behaviour Phoenix.LiveComponent`:

      handle_event/3   {:reply, payload, socket}  ->  {:noreply, socket}
      handle_call/3    {:reply, reply, socket}    ->  {:noreply, socket}
      mount/3          {:ok, socket, opts}         ->  {:ok, socket}

  A survivor means no test checks the dropped element — the JS-hook reply payload, or the
  `mount` `temporary_assigns:` / `layout:` option. A `Phoenix.LiveComponent`'s `handle_event/3`
  returns the same `{:reply, payload, socket}` shape, so its reply payload is the same untested
  seam; the `{:ok, socket, opts}` (mount) reshape simply never matches a component return.

  Recognised by tuple shape, independent of which callback it sits in. The 2-tuples
  `{:noreply, socket}` / `{:ok, socket}` have nothing to drop and are left alone. Silence a
  site with `# mutare:ignore[lv_reply]`.

  Under `--no-expand-uses` the `@behaviour` that `use Phoenix.LiveView` / `use
  Phoenix.LiveComponent` injects is invisible, so `:lv_reply` no-ops; a direct `@behaviour`
  still works.
  """
  @behaviour Mutare.Mutator
  @behaviour Mutare.Mutator.Structural

  alias Mutare.AST

  # The behaviours whose callbacks return the reshapeable tuples. `Phoenix.LiveComponent`'s
  # `handle_event/3` shares the `{:reply, payload, socket}` shape, so it is gated in too.
  @gated_behaviours [Phoenix.LiveView, Phoenix.LiveComponent]

  @impl Mutare.Mutator
  @spec name() :: :lv_reply
  def name, do: :lv_reply

  # Every decision needs the enclosing module's behaviours, so this mutator works purely
  # through the structural return hook — never node-locally.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  @doc """
  Offer the reshaped LiveView return for `tail`, but only inside a module that implements one
  of `#{inspect(@gated_behaviours)}` (read from `context.behaviours`). The behaviour-aware
  variant of `c:Mutare.Mutator.Structural.return_replacements/1`.
  """
  @impl Mutare.Mutator.Structural
  @spec return_replacements(Macro.t(), Mutare.Mutator.Structural.context()) :: [Macro.t()]
  def return_replacements(tail, %{behaviours: behaviours}) do
    if Enum.any?(@gated_behaviours, &MapSet.member?(behaviours, &1)),
      do: mutate_return(tail),
      else: []
  end

  # A 3-element tuple carries its own metadata (`{:{}, meta, [tag | rest]}`). The engine hands
  # us the return tail directly — a reshapeable tuple arrives as this node, never wrapped in a
  # `:__block__` (Sourceror only block-wraps bare literals like an atom or number, and the
  # returns analyzer already descends a multi-statement block to its last statement), so there
  # is no block layer for us to peel. Only the 3-tuples carry a droppable trailing element; a
  # 2-tuple has nothing to drop.
  @spec mutate_return(Macro.t()) :: [Macro.t()]
  defp mutate_return({:{}, _meta, [tag | rest]}) when is_list(rest),
    do: returns_for(tag_name(tag), rest)

  defp mutate_return(_tail), do: []

  # Drop the optional trailing element, keeping a valid LiveView return:
  #   {:reply, payload, socket} -> {:noreply, socket}   (handle_event / handle_call)
  #   {:ok, socket, opts}       -> {:ok, socket}         (mount)
  @spec returns_for(atom() | nil, [Macro.t()]) :: [Macro.t()]
  defp returns_for(:reply, [_payload, socket]), do: [retuple(:noreply, [socket])]
  defp returns_for(:ok, [socket, _opts]), do: [retuple(:ok, [socket])]
  defp returns_for(_tag, _elements), do: []

  # Build `{:tag, value}` as a Sourceror tuple node. The explicit `{:{}, [], [...]}` form
  # renders a 2-element arg list as the literal 2-tuple `{tag, value}`.
  @spec retuple(atom(), [Macro.t()]) :: Macro.t()
  defp retuple(tag, values), do: {:{}, [], [AST.literal(tag) | values]}

  # The atom of a control tag. Sourceror always wraps a tuple element's atom literal in a
  # block, so the tag arrives as `{:__block__, _, [atom]}`; anything else (a computed tag, a
  # non-atom) is not a tag we reshape.
  @spec tag_name(Macro.t()) :: atom() | nil
  defp tag_name({:__block__, _meta, [atom]}) when is_atom(atom), do: atom
  defp tag_name(_other), do: nil
end
