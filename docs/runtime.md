# runtime design

## goal

osmium should behave like a native shell around one persistent bun app process.

swift is there to host native controls and render views.
bun is there to own app state, decisions, and protocol glue.

## shape

- one native app process
- one persistent bun child process
- line-delimited json over stdin/stdout
- swift sends events and context snapshots
- bun returns new state plus optional intents

## event loop

1. swift observes user or native events
2. swift sends `{ method, params }` to bun
3. bun reduces state
4. bun returns:
   - state for swift to render
   - rows/view models for current surface
   - intents for native execution
5. swift applies state and executes intents

## data model

prefer plain snapshots over chatty imperative commands.

good:

```json
{ "state": { "mode": "picker" }, "rows": [{ "primaryText": "notes.txt" }] }
```

bad:

```json
{ "ops": ["append row", "select row 2", "clear previous rows"] }
```

snapshots are easier to debug, easier to test, and simpler to version.

## intents

intents are the boundary where bun asks swift to do native work.

examples:

- open editor for a path
- open web view for a url or file
- run a command in a terminal surface
- focus a tab

bun should not know how `wkwebview`, `nstextview`, or `swiftterm` are embedded.
it should only know the intent it wants.

## failure model

if the bun bridge dies:

- swift should restart it lazily
- bun-owned ephemeral ui state can reset
- durable state should come from disk or explicit reload calls

the bridge api should stay small enough that restart is cheap.

## guardrails

- no app logic in swift unless it is inseparable from a native widget
- no duplicated reducers in swift and bun
- no hidden config interpretation in swift
- keep bridge messages coarse enough to avoid per-keystroke complexity explosions
