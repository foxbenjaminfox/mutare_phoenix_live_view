defmodule Demo.PageControllerTest do
  use ExUnit.Case

  alias Demo.PageController

  # create asserts only the *body*, never the status — so swapping :created for another
  # success (:ok / :accepted) is invisible. A missing status assertion: `:http_status` (a
  # re-exported base family) survives.
  test "create returns the new record" do
    conn = PageController.create(%Plug.Conn{}, %{})
    assert conn.resp_body == %{id: 1}
  end
end
