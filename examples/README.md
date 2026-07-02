# Examples

A **standalone mini-project** used as a target for Mutare, demonstrating the
`mutare_phoenix_live_view` families alongside the base `mutare_phoenix` families it composes
with. Run it from the repo root (compile the packages first so the mutators are on the
code path):

```
mix compile
mix mutare examples/demo
```

| Example | Surface | What it demonstrates |
| --- | --- | --- |
| [`demo`](demo/) | LiveView + auth hook + controller | An untested navigation kind (`:lv_nav`), a dropped reply/option (`:lv_reply`), an unasserted stream op (`:lv_stream`), a dropped client event (`:lv_event`), an unnotified component (`:lv_send_update`), the auth-bypass via the built-in `:convention`, and the composed-in base family (`:http_status`) — one or more survivors per family, plus the kills that prove the families catch what *is* asserted. |

The project has **partial test coverage on purpose**: each run surfaces real survivors, and
the `README.md` walks through the test-quality gap behind each one. The recurring lesson is the
package's thesis — when a LiveView callback's behaviour *is* its socket transformation and the
tuple it returns, a test that asserts "something happened" but not *which* transformation (or
*which* tuple) leaves a gap Mutare will find.
