# Demo: a full-stack Phoenix LiveView surface

A standalone mini-project modelling the **socket-transform surface** of a LiveView app — a
LiveView, a LiveView auth hook, and a controller — over tiny stand-ins for `Phoenix.LiveView`
/ `Plug.Conn` / `Phoenix.Controller` (so it needs no real Phoenix). The custom mutators match
calls and behaviours by module *name*, so the mutations are exactly what they'd be against a
real app.

A LiveView callback's contract is **which socket-transforming call ran and what tuple it
returned** — the navigation kind, the reply it sent, the stream op it performed, the child
component it refreshed, whether an auth hook continued or halted. These are precisely the things
a suite tends to under-assert, and each gap becomes a survivor.

From the repo root (compile the packages once so the mutators are loadable):

```
mix compile
mix mutare examples/demo
```

Expected (file order):

```
mutare in examples/demo: 16 mutants across 3 file(s)

lib/demo/page_controller.ex:13  [http_status, in-place]  SURVIVED
-    |> Plug.Conn.put_status(:created)
+    |> Plug.Conn.put_status(:ok)

lib/demo/page_controller.ex:13  [http_status, in-place]  SURVIVED
-    |> Plug.Conn.put_status(:created)
+    |> Plug.Conn.put_status(:accepted)

lib/demo/songs_live.ex:20  [lv_reply, in-place]  SURVIVED
-    {:ok, socket, temporary_assigns: [songs: []]}
+    {:ok, socket}

lib/demo/songs_live.ex:27  [lv_nav, in-place]  SURVIVED
-    {:noreply, Phoenix.LiveView.push_navigate(socket, to: "/songs/" <> id)}
+    {:noreply, Phoenix.LiveView.push_patch(socket, to: "/songs/" <> id)}

lib/demo/songs_live.ex:34  [lv_reply, in-place]  SURVIVED
-    {:reply, %{pong: true}, socket}
+    {:noreply, socket}

lib/demo/songs_live.ex:40  [lv_stream, in-place]  SURVIVED
-    {:noreply, Phoenix.LiveView.stream_insert(socket, :songs, %{id: name, name: name})}
+    {:noreply, Phoenix.LiveView.stream_delete(socket, :songs, %{id: name, name: name})}

lib/demo/songs_live.ex:47  [lv_event, in-place]  SURVIVED
-    {:noreply, Phoenix.LiveView.push_event(socket, "highlight", %{id: id})}
+    {:noreply, socket}

lib/demo/songs_live.ex:55  [lv_send_update, in-place]  SURVIVED
-    Phoenix.LiveView.send_update(Demo.CartComponent, id: "cart", count: count)
+    :ok

lib/demo/user_auth.ex:21  [convention, in-place]  SURVIVED
-      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
+      {:cont, Phoenix.LiveView.redirect(socket, to: "/login")}

mutation score: 43.8%  (7 killed, 9 survived, 16 total)
```

Every family on show produces a survivor — and the kills (below) prove the suite *does* catch
what it asserts.

## The LiveView survivors (this package)

- **`:lv_nav` — the untested navigation kind** (`SongsLive` "open"). The view does a
  `push_navigate` — dismount this LiveView and **mount** the song's. The test only checks that
  *some* navigation happened, so swapping it for a `push_patch` (keep the process, just re-run
  `handle_params/3` — in-process state silently preserved) is invisible.
  `Phoenix.LiveViewTest`'s `assert_patch` vs `assert_redirect` is exactly the assertion that
  would kill it.

- **`:lv_reply` — the dropped reply / option** (`SongsLive.mount` and "ping"). `mount` declares
  a `temporary_assigns:` option and "ping" replies to a JS hook with a payload — but the tests
  check only that mount *succeeded* and that the socket *came back*, never the option or the
  reply. So dropping the trailing element (`{:ok, s, opts}` → `{:ok, s}`,
  `{:reply, _, s}` → `{:noreply, s}`) survives.

- **`:lv_stream` — the unasserted stream op** (`SongsLive` "add"). The view
  inserts a song into the `:songs` stream; the test only checks the event returned `:noreply`,
  never the stream contents. So inverting the insert into a `stream_delete` survives — a
  high-equivalent family in apps that don't assert stream contents.

- **`:lv_event` — the dropped client event** (`SongsLive` "select"). The view
  pushes a `"highlight"` event to the client's JS hook; the test only checks the event
  returned `:noreply`, never that the client was told anything. So removing the `push_event`
  entirely is invisible — the LiveView sibling of a forgotten `halt`, killed only by
  `assert_push_event`.

- **`:lv_send_update` — the unnotified component** (`SongsLive` "refresh"). The view tells the
  cart **component** to re-render with the new count via `send_update`; the test only checks the
  event returned `:noreply`, never that the component was notified. So removing the `send_update`
  (it collapses to `:ok`, the value it returns — not the socket) is invisible — the
  server→component sibling of `:lv_event`, killed only by asserting the component re-rendered
  (`render_component`).

## The auth-bypass survivor (a Mutare built-in)

- **`:convention` — the untested rejection path** (`UserAuth.on_mount`). The hook returns
  `{:cont, socket}` for an authenticated mount and `{:halt, redirect(...)}` for an anonymous
  one. The test pins the `:cont` path (so `:cont → :halt` is **killed**) but asserts only that
  the anonymous path returned *a socket*, never that it **halted**. So `:halt → :cont` — an
  anonymous request now allowed straight through to the guarded LiveView, the classic
  auth-bypass — survives. **No mutator in this package does this**: `:cont` ↔ `:halt` is a
  built-in `Mutare.Mutators.ConventionAtom` swap (on by default), which matches the atom
  literal regardless of module/behaviour. The marquee LiveView auth coverage comes for free.

## The mutare_phoenix survivor

- **`:http_status`** (`PageController.create`) — answers `201 Created` but the test asserts
  only the body, so swapping `:created` for another success (`:ok`/`:accepted`) survives.

Composing the two presets (`Mutare.Phoenix.all() ++ Mutare.Phoenix.LiveView.all()`) enables the
whole stack: the LiveView families **and** the conn-level base families.

## What the kills prove

The 7 killed mutants are the control: `:cont → :halt` (the authenticated path *is* asserted),
`:ok → :error` on `mount`'s tag (`mount succeeds` asserts `:ok`), and five `clause_drop`s on
the `handle_event/3` clauses (each event *is* exercised). The suite catches what it checks —
mutation testing's value is everything it *doesn't*.

> Why `:ok → :error` (or `:mutare`) doesn't already cover `:http_status`, and why `:reply`
> isn't covered by `:convention`: in those positions the built-in atom swaps **crash** rather
> than producing a valid-but-wrong value (an uninformative kill). The package families swap to
> a *valid* alternative, so a survivor means a genuine missing assertion.
