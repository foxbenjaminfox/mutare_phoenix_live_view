defmodule Mutare.Phoenix.LiveView.Navigation do
  @moduledoc """
  `:lv_nav` — swaps a LiveView's socket-navigation call between its two patch/navigate forms:

      push_navigate(socket, to: p)  <->  push_patch(socket, to: p)

  `push_navigate` dismounts the current LiveView and mounts a new one (state discarded);
  `push_patch` keeps the process and only re-invokes `handle_params/3`. `Phoenix.LiveViewTest`
  separates them (`assert_patch` vs `assert_redirect`), so a test that asserts *how* navigation
  happened kills the mutant.

  One caveat on the `push_navigate → push_patch` direction: `push_patch` is only valid to the
  *same* LiveView, so patching to a route backed by a *different* LiveView raises at runtime —
  an uninformative kill (any test exercising the line dies) rather than a survivor. The common
  same-LiveView case is a genuine seam, and the `push_patch → push_navigate` direction is always
  valid.

  Matches direct (`Phoenix.LiveView.push_navigate(...)`), aliased, and bare-imported
  (`use`-injected) calls. Silence a site with `# mutare:ignore[lv_nav]`.

  Also registers the LiveView compile-time DSL as `:skip` — the `Phoenix.LiveView.Router`
  route declarations (`live`/`live_session`), `on_mount` hook declarations, and
  `Phoenix.Component`'s declarative assigns and template embedding (`attr`/`slot`/
  `embed_templates`) — so Mutare leaves those compile-time declarations unmutated.
  """
  @behaviour Mutare.Mutator
  @behaviour Mutare.MacroRouting

  alias Mutare.Calls
  alias Mutare.Mutator

  # The `rebuild` closure `Calls.resolved_call_to/3` hands back: re-emits the call in its
  # written form with a new function name and argument list.
  @typep rebuild :: (atom(), [Macro.t()] -> Macro.t())

  # The LiveView compile-time DSL, registered `:skip` so core leaves the declarations raw.
  # `:any` arity covers every written form (`live/2..4`, `live_session/2..3`, `attr/2..3`, …).
  @dsl_skips [
    # Route declarations (`import Phoenix.LiveView.Router` in the consumer's router).
    {Phoenix.LiveView.Router, :live},
    {Phoenix.LiveView.Router, :live_session},
    # Lifecycle hook declaration at the top of a LiveView module.
    {Phoenix.LiveView, :on_mount},
    # Declarative assigns / template embedding (`Phoenix.Component`, imported by
    # `use Phoenix.LiveView` / `use Phoenix.LiveComponent`).
    {Phoenix.Component, :attr},
    {Phoenix.Component, :slot},
    {Phoenix.Component, :embed_templates}
  ]

  @impl Mutare.Mutator
  @spec name() :: :lv_nav
  def name, do: :lv_nav

  # Defensive, not a route mutator: `live`/`live_session` routes, `on_mount` declarations, and
  # `attr`/`slot`/`embed_templates` declarations are compile-time code that runs once as
  # mutant 0, so mutations inside them can never activate under Mutare's compile-once model.
  # Skipping the DSL keeps core from wasting mutant ids on it. LiveView *callback* bodies are
  # ordinary runtime code and are still mutated.
  @impl Mutare.MacroRouting
  @spec macro_routes() :: [Mutare.MacroRouting.route()]
  def macro_routes, do: for({module, name} <- @dsl_skips, do: {module, name, :any, :skip})

  # Never fires node-locally: the arity guard needs pipe context — a piped
  # `s |> push_navigate(to: p)` writes one arg but is effectively arity 2.
  @impl Mutare.Mutator
  @spec mutate(Macro.t()) :: :skip
  def mutate(_node), do: :skip

  # The engine's `Mutare.Mutator.mutations/3` always threads a context carrying `:pipe_mode`
  # (a required key of `t:Mutare.Mutator.context/0`), so this `%{pipe_mode: …}` head is total
  # over every context that can reach it. No catch-all clause: one would be dead code, and were
  # the engine to ever drop `:pipe_mode` a `FunctionClauseError` surfaces that far better than a
  # silent `:skip` masking the contract breach.
  @impl Mutare.Mutator
  @spec mutate(Macro.t(), Mutator.context()) :: :skip | [Macro.t()]
  def mutate(node, %{pipe_mode: pipe_mode}) do
    case Calls.resolved_call_to(node, Phoenix.LiveView) do
      {:ok, fun, args, rebuild} -> nav_swaps(fun, args, pipe_mode, rebuild)
      :error -> :skip
    end
  end

  # The sibling navigation for each recognised call, args reused verbatim:
  #
  #   * `push_navigate` — to `push_patch` (the remount↔patch seam, the headline);
  #   * `push_patch` — back to `push_navigate`.
  #
  # `redirect` is *not* a source for `:lv_nav`: its `to:`/`external:` kind is a different
  # axis from the remount↔patch navigation seam, and this package leaves it unmutated.
  @spec nav_swaps(atom(), [Macro.t()], Mutator.pipe_mode(), rebuild()) :: :skip | [Macro.t()]
  defp nav_swaps(:push_navigate, args, pipe_mode, rebuild),
    do: swap_when_arity_2(args, pipe_mode, fn -> rebuild.(:push_patch, args) end)

  defp nav_swaps(:push_patch, args, pipe_mode, rebuild),
    do: swap_when_arity_2(args, pipe_mode, fn -> rebuild.(:push_navigate, args) end)

  defp nav_swaps(_fun, _args, _pipe_mode, _rebuild), do: :skip

  # `push_navigate/2` and `push_patch/2` share exactly one arity (2). Guarding on it both
  # documents that assumption and keeps every metamutant compiling should either function ever
  # gain an arity the other lacks (the asymmetry `:lv_stream`'s arity gate already guards).
  @spec swap_when_arity_2([Macro.t()], Mutator.pipe_mode(), (-> Macro.t())) :: :skip | [Macro.t()]
  defp swap_when_arity_2(args, pipe_mode, build) do
    if Mutator.effective_arity(args, pipe_mode) == 2, do: [build.()], else: :skip
  end
end
