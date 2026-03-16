# migration plan

## north star

the app should feel like:

- swift shell
- bun brain

not:

- swift app with a few bun helpers

## phase 1

move sidebar/tab/picker logic into bun.

status:

- mostly done
- reducer lives in `src/sidebar/engine.ts`
- persistent bridge lives in `src/app/bridge.ts`

remaining cleanup:

- remove old picker support once nothing else uses it
- make tab model itself bun-owned instead of re-derived from swift

## phase 2

move agent feed/session state into bun.

deliverables:

- agent reducer
- explicit agent bridge methods
- swift agent surfaces become renderers + native widgets

## phase 3

move surface registry and title policy into bun.

deliverables:

- bun-owned list of surfaces/tabs
- cwd/title updates as events into bun
- bun emits open/focus/run intents

## phase 4

shrink swift config logic to raw value access only.

deliverables:

- bun handles yaml parsing, defaults, migrations
- swift reads resolved flat config only

## phase 5

optional, only if needed:

- bun-driven command palette
- bun-owned session restore
- multi-window state

## constraints

- do not rewrite native widgets just for purity
- keep bridge methods coarse and testable
- each phase should leave fewer decisions in swift than before
- every moved reducer should get bun-side tests before deleting old swift logic
