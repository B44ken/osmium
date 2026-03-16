# ownership

## principle

bun owns meaning.
swift owns pixels and native handles.

if a behavior can be expressed as pure state + events, it belongs in bun.

## bun owns

- config defaults and interpretation
- tab model
- sidebar and picker reducers
- file-browser rules
- agent feed/session state
- title and cwd derivation policy
- routing decisions like editor vs browser vs terminal
- persistence and resume logic

## swift owns

- app window and layout
- animations
- terminal/editor/webview embedding
- focus and responder plumbing
- native file dialogs
- system open / process launch execution
- rendering state returned by bun

## shared seam

swift sends:

- key and click events
- native observations
- surface metadata snapshots

bun sends:

- reduced state
- render rows/models
- intents

## smells

these are signs logic is drifting back into swift:

- swift computes filtered lists
- swift decides which surface type to open for a file
- swift derives titles from cwd heuristics
- swift mutates agent feed structure directly
- swift needs its own copy of config fallback logic

## practical exception

some native details will stay in swift because appkit makes that cheaper:

- exact animation timing
- first responder management
- view reuse and sizing
- terminal control integration

that is fine as long as swift is not deciding product behavior.
