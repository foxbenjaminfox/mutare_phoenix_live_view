defmodule Mutare.Phoenix.LiveView do
  @moduledoc """
  [Mutare](https://hex.pm/packages/mutare) mutators for the **Phoenix LiveView** surface:
  socket navigation, callback reply tuples, stream operations, and pushed client events.

  This package depends on `mutare_phoenix`, so the base conn-level families are on your code
  path too; compose the two presets for a full-stack app (see "Usage").

  ## Families

    * `Mutare.Phoenix.LiveView.Navigation` — `:lv_nav`: swap `push_navigate` ↔ `push_patch`.
    * `Mutare.Phoenix.LiveView.Reply` — `:lv_reply`: drop a callback's optional trailing tuple
      element (`{:reply, payload, socket}` → `{:noreply, socket}`, `{:ok, socket, opts}` →
      `{:ok, socket}`). Fires in `@behaviour Phoenix.LiveView` / `Phoenix.LiveComponent` modules.
    * `Mutare.Phoenix.LiveView.Stream` — `:lv_stream`: swap `stream_insert` ↔ `stream_delete`.
    * `Mutare.Phoenix.LiveView.Event` — `:lv_event`: remove `push_event/3`.
    * `Mutare.Phoenix.LiveView.SendUpdate` — `:lv_send_update`: remove `send_update/2,3` /
      `send_update_after/3,4` (the `LiveComponent` sibling of `:lv_event`'s dropped client push).

  Auth-hook `:cont`/`:halt` decisions (`on_mount`/`attach_hook`) are covered by Mutare's
  built-in `:convention` family (on by default), not by this package.

  ## Usage

  Splice `all/0` into `:mutators` in your `.mutare.exs` alongside the `:builtins` group token
  (which keeps Mutare's own families on, including `:convention`):

      # .mutare.exs — a LiveView app
      [mutators: [:builtins] ++ Mutare.Phoenix.LiveView.all()]

  A full-stack app that also wants the conn-level base families composes all three groups:

      # .mutare.exs — a full-stack Phoenix + LiveView app
      [mutators: [:builtins] ++ Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()]

  `all/0` returns only the five LiveView families — it does not include the base
  `mutare_phoenix` families, so compose `Mutare.Phoenix.all/0` explicitly as shown above.

  To drop a family that is too noisy for your suite (e.g. `:lv_stream`, `:lv_event`, or
  `:lv_send_update` in an app that never asserts stream contents, pushed events, or component
  updates), leave it out of the list you splice in, or silence individual sites with
  `# mutare:ignore[lv_stream]`.

  The package matches module *names* (`Phoenix.LiveView`), so it depends on neither
  `phoenix_live_view` nor `phoenix` — resolution happens in your project, where they are
  present.
  """

  alias Mutare.Phoenix.LiveView.{Event, Navigation, Reply, SendUpdate, Stream}

  @doc """
  This package's five LiveView mutator families — `Navigation`, `Reply`, `Stream`, `Event`,
  `SendUpdate`.

  It does **not** include the base `mutare_phoenix` families; compose those explicitly with
  `Mutare.Phoenix.all/0` when you want the full Phoenix + LiveView surface (see the moduledoc's
  "Usage").

      iex> Mutare.Phoenix.LiveView.all()
      [Mutare.Phoenix.LiveView.Navigation, Mutare.Phoenix.LiveView.Reply,
       Mutare.Phoenix.LiveView.Stream, Mutare.Phoenix.LiveView.Event,
       Mutare.Phoenix.LiveView.SendUpdate]
  """
  @spec all() :: [module(), ...]
  def all, do: [Navigation, Reply, Stream, Event, SendUpdate]
end
