defmodule Demo.UserAuth do
  @moduledoc """
  A LiveView lifecycle hook — the canonical place an authorization decision lives. `on_mount/4`
  returns `{:cont, socket}` to let the mount proceed or `{:halt, redirect(...)}` to reject it.

  No mutator in *this* package touches the decision: the `:cont` ↔ `:halt` swap is **already**
  a Mutare built-in (`Mutare.Mutators.ConventionAtom`, the `:convention` family, on by
  default), which matches the atom literal wherever it appears — module, behaviour, and `fn`
  body irrelevant. Flipping `:halt` → `:cont` is the auth-bypass mutation; a suite that never
  exercises the rejection path lets it survive.
  """

  @doc """
  Continue an authenticated mount; otherwise **halt** and redirect to the login page so the
  guarded LiveView never mounts.
  """
  def on_mount(:require_user, _params, session, socket) do
    if session["user_id"] do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end
end
