# app bridge api

see also:

- [docs/runtime.md](/Users/brad/git/osmium/docs/runtime.md)
- [docs/ownership.md](/Users/brad/git/osmium/docs/ownership.md)
- [docs/agent.md](/Users/brad/git/osmium/docs/agent.md)
- [docs/migration.md](/Users/brad/git/osmium/docs/migration.md)

## direction

bun owns state and decisions.
swift renders native views, forwards events, and executes native intents.

## process

- one persistent bun process
- line-delimited json over stdin/stdout
- request:

```json
{ "id": 1, "method": "sidebar/reduce", "params": { "state": {}, "context": {}, "action": {} } }
```

- response:

```json
{ "id": 1, "result": { "sidebar": { "state": {}, "rows": [], "selectionIndex": 0, "intent": null } } }
```

## sidebar api

### state

```json
{
  "mode": "hidden | tabsPeek | picker",
  "pickerQuery": "",
  "pickerSelectionIndex": -1,
  "pickerSource": null
}
```

### context

```json
{
  "tabs": [{ "id": "", "kind": "", "kindPrefix": "", "title": "", "currentThreadId": null }],
  "selectedTabId": null,
  "currentSurface": { "kind": "", "cwd": "", "threadId": null },
  "recentThreadsStatus": "idle | loading | loaded",
  "recentThreads": [{ "threadId": "", "cwd": "", "title": "", "preview": "", "updatedAt": 0 }]
}
```

### actions

- `togglePicker`
- `dismiss`
- `showTabsPeek`
- `hideTabsPeek`
- `surfaceChanged`
- `refresh`
- `cycleTabs { delta }`
- `sidebarKey { keyCode, key, modifiers }`
- `clickRow { row }`

### intents

- `selectTab { tabId }`
- `replaceAgentThread { threadId, cwd }`
- `openBrowser { path }`
- `openEditor { path }`
- `runExecutable { path }`
- `openSystem { path }`

## agent api

### methods

- `agent/reduce`

### actions

- `submit { prompt }`
- `bridgeEvent { event }`
- `turnExit { completed, cancelled, stderrText, terminationStatus, terminationReason }`
- `replaceThread { snapshot }`
- `scrollFollow { followsBottom }`

### state

```json
{
  "cwd": "",
  "threadId": null,
  "title": null,
  "busy": false,
  "shouldAutoScroll": true,
  "rows": [],
  "activeAssistant": null
}
```

### rows

- `message { id, tone, text, phase? }`
- `activity { id, activity, badge?, title, detail?, text?, lines[] }`

notes:

- `phase` is `commentary | final_answer` when the upstream item provides it
- `badge` is the leading monospace tag for compact metadata
- trace rows use it for durations when present
- edit rows use it for diffstat, like `+50 -100`

## codex api

for reuse outside osm, prefer a small codex app-server client instead of the agent bridge.

module:

- `src/agent/usecodex.ts`

surface:

- `CodexClient.create(options)`
- `client.listModels(limit?)`
- `client.listThreads(limit?)`
- `client.readThread(threadId)`
- `client.stream(input, options?)`
- `client.close()`

notes:

- this owns raw codex app-server json-rpc
- it returns codex thread/turn events
- osm-specific row normalization stays in `src/agent/bridge.ts`

### editor contract

- the editor surface is a `wkwebview` hosting monaco
- `osm edit` opens monaco with wrapped lines on
- `osm edit <file> --hot <command>` stores `<command>` on that editor tab
- the agent composer wraps to the visible input width
- save writes the latest mirrored webview buffer back to disk
- if the editor has a hot command, save runs it in a dedicated osm terminal tab instead of the shell that launched `osm`

### config contract

- `options.start_dir` is the yaml key for the default cwd
- root-level `start_dir` is accepted only as a backwards-compat fallback

### agent feed contract

- rows stay in event order
- assistant text may be split across multiple message rows
- tool/edit activity inserts between assistant text segments when events land there
- `activeAssistant { turnId, itemId, rowId }` tracks the currently streaming assistant segment

## next

move agent feed/session reduction into the same bridge, then surface registry/title logic.
