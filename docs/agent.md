# agent design

## goal

agent should be a bun-owned state machine rendered by swift.

today the bridge mostly owns model execution and trace normalization.
the next step is to move feed/session state there too.

## target split

bun owns:

- current thread id
- thread title
- feed rows
- tool/trace/edit normalization
- message grouping
- autoscroll policy decisions
- model + thinking defaults
- recent thread loading and thread replacement logic

swift owns:

- feed row rendering
- text layout / lightweight markdown rendering
- composer input widget
- scrolling widget
- native copy/select behavior

## recommended api shape

methods:

- `agent/create`
- `agent/submit`
- `agent/stop`
- `agent/select-model`
- `agent/select-thinking`
- `agent/load-thread`
- `agent/observe-scroll`

state:

```json
{
  "threadId": "",
  "title": "",
  "rows": [],
  "composer": { "model": "", "thinking": "", "busy": false },
  "scroll": { "follow": true }
}
```

## row model

keep row types explicit and normalized:

- `user`
- `assistant`
- `trace`
- `toolCall`
- `edit`
- `error`

swift should not infer row meaning from ad hoc strings.

## markdown stance

markdown support should stay intentionally small:

- headings
- bold
- inline code
- fenced code blocks

parsing can live in bun or swift.
rendering must stay in swift.

## win condition

opening a thread, sending a prompt, receiving tool calls, and replacing the current chat should all be explainable as:

- event into bun
- reduced agent state out
- swift render
