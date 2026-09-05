defmodule Demo.PageController do
  @moduledoc """
  A plain controller action, included to show the **base `mutare_plug` / `mutare_phoenix`
  families compose in** — a full-stack app lists
  `[:builtins] ++ Mutare.Plug.all() ++ Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()`
  and gets the LiveView, controller-level, *and* conn-level families. Its conn transformations are under-asserted exactly
  as in the base package's demo.
  """

  @doc "Create a record and answer 201 Created — the test checks only the body (`:http_status`)."
  def create(conn, _params) do
    conn
    |> Plug.Conn.put_status(:created)
    |> Phoenix.Controller.json(%{id: 1})
  end
end
