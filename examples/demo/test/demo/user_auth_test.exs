defmodule Demo.UserAuthTest do
  use ExUnit.Case

  alias Demo.UserAuth

  defp socket, do: %Phoenix.LiveView{}

  # The authenticated path is pinned down: it asserts `{:cont, _}`, so the `:cont → :halt`
  # mutant is killed.
  test "lets an authenticated mount continue" do
    socket = socket()

    assert {:cont, ^socket} =
             UserAuth.on_mount(:require_user, %{}, %{"user_id" => 1}, socket)
  end

  # The rejection path *is* exercised — but the assertion is too weak. It checks only that the
  # hook returned *a* socket, never that it **halted**. So flipping `:halt` → `:cont` (an
  # anonymous request now allowed straight through to the guarded LiveView — the classic
  # auth-bypass) changes nothing this test looks at: the `:halt → :cont` mutant survives. The
  # missing `assert {:halt, _} = …` is the gap the built-in `:convention` surfaces.
  test "handles an anonymous mount" do
    {_decision, returned} = UserAuth.on_mount(:require_user, %{}, %{}, socket())
    assert %Phoenix.LiveView{} = returned
  end
end
