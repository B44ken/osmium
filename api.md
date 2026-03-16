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

- `message { id, tone, text }`
- `activity { id, activity, title, detail?, text?, lines[] }`

### editor contract

- `osm edit` uses wrapped lines
- the agent composer wraps to the visible input width
- option-left/right and option-backspace/delete follow appkit word boundaries
- cmd-left/right move to line start/end
- cmd-up/down move to document start/end

### config contract

- `start_dir` is a top-level yaml string
- when osmium needs a fallback cwd, it uses `start_dir`

### agent feed contract

- rows stay in event order
- assistant text may be split across multiple message rows
- tool/edit activity inserts between assistant text segments when events land there
- `activeAssistant { turnId, itemId, rowId }` tracks the currently streaming assistant segment

## next

move agent feed/session reduction into the same bridge, then surface registry/title logic.
