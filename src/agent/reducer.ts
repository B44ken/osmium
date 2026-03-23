import type { AgentBridgeEvent, BridgeThreadSnapshot, BridgeFeedItem } from './bridge.ts'

export type AgentRow =
  | { id: string; kind: 'message'; tone: 'assistant' | 'user' | 'status' | 'error'; text: string; phase?: 'commentary' | 'final_answer' }
  | { id: string; kind: 'activity'; activity: 'trace' | 'edit'; badge?: string; title: string; detail?: string; text?: string; lines: string[] }

type ActiveAssistant = {
  turnId: string
  itemId: string
  rowId: string
}

export type AgentReducerState = {
  cwd: string
  threadId: string | null
  title: string | null
  busy: boolean
  shouldAutoScroll: boolean
  rows: AgentRow[]
  activeAssistant: ActiveAssistant | null
}

export type AgentReducerAction =
  | { type: 'submit'; prompt: string }
  | { type: 'bridgeEvent'; event: AgentBridgeEvent }
  | { type: 'turnExit'; completed: boolean; cancelled: boolean; stderrText?: string | null; terminationStatus: number; terminationReason: 'exit' | 'uncaughtSignal' }
  | { type: 'replaceThread'; snapshot: BridgeThreadSnapshot }
  | { type: 'scrollFollow'; followsBottom: boolean }

export const initialAgentState = (cwd: string): AgentReducerState => ({
  cwd,
  threadId: null,
  title: null,
  busy: false,
  shouldAutoScroll: true,
  rows: [],
  activeAssistant: null,
})

export function reduceAgent(rawState: AgentReducerState | null | undefined, cwd: string, action: AgentReducerAction): AgentReducerState {
  const state = rawState ?? initialAgentState(cwd)

  switch (action.type) {
    case 'submit':
      return submit(state, action.prompt)
    case 'bridgeEvent':
      return handleBridgeEvent(state, action.event)
    case 'turnExit':
      return handleTurnExit(state, action)
    case 'replaceThread':
      return replaceThread(action.snapshot)
    case 'scrollFollow':
      return { ...state, shouldAutoScroll: action.followsBottom }
  }
}

function submit(state: AgentReducerState, prompt: string): AgentReducerState {
  const trimmed = prompt.trim()
  if (!trimmed || state.busy)
    return state

  const next = appendMessage(state, {
    tone: 'user',
    text: trimmed,
  })

  return {
    ...next,
    title: state.title ?? makeConversationTitle(trimmed),
    busy: true,
    activeAssistant: null,
    shouldAutoScroll: true,
  }
}

function handleBridgeEvent(state: AgentReducerState, event: AgentBridgeEvent): AgentReducerState {
  switch (event.type) {
    case 'thread.started':
    case 'thread.resumed':
      return { ...state, threadId: event.threadId }
    case 'turn.started':
      return { ...state, activeAssistant: null }
    case 'delta':
      return appendAssistantDelta(state, event)
    case 'message':
      return completeMessageItem(state, event)
    case 'trace':
      return appendActivity(state, {
        activity: 'trace',
        badge: event.badge,
        title: event.title,
        detail: event.detail,
        text: event.text,
        lines: event.lines ?? [],
      })
    case 'edit':
      return appendActivity(state, {
        activity: 'edit',
        badge: event.badge,
        title: event.title,
        detail: event.detail,
        text: event.text,
        lines: event.lines ?? [],
      })
    case 'completed':
      return completeTurn(state, event)
    case 'error':
      return {
        ...setAssistantMessage(state, event.message, 'error'),
        shouldAutoScroll: true,
      }
    default:
      return state
  }
}

function completeTurn(state: AgentReducerState, event: Extract<AgentBridgeEvent, { type: 'completed' }>): AgentReducerState {
  let next: AgentReducerState = { ...state, threadId: event.threadId, activeAssistant: null }

  if (event.text)
    next = ensureAssistantCompletedText(next, event.text)

  if (event.error)
    next = {
      ...setAssistantMessage(next, assistantErrorText(next, event.error), 'error'),
    }

  return {
    ...next,
    shouldAutoScroll: true,
  }
}

function handleTurnExit(
  state: AgentReducerState,
  exit: Extract<AgentReducerAction, { type: 'turnExit' }>,
): AgentReducerState {
  let next: AgentReducerState = { ...state, busy: false, activeAssistant: null }
  if (exit.completed)
    return next

  if (exit.cancelled) {
    const text = assistantText(next)
    if (text) {
      next = setAssistantMessage(next, `${text}\n\nStopped.`, 'status')
    } else {
      next = appendMessage(next, { tone: 'status', text: 'Stopped.' })
    }
    return {
      ...next,
      shouldAutoScroll: true,
    }
  }

  const fallback = exit.terminationReason === 'exit'
    ? `Agent bridge exited with status ${exit.terminationStatus}.`
    : 'Agent bridge terminated unexpectedly.'
  const message = exit.stderrText?.trim() || fallback
  next = setAssistantMessage(next, message, 'error')
  return {
    ...next,
    shouldAutoScroll: true,
  }
}

function replaceThread(snapshot: BridgeThreadSnapshot): AgentReducerState {
  let next: AgentReducerState = {
    ...initialAgentState(snapshot.cwd),
    threadId: snapshot.threadId,
    title: snapshot.title,
  }

  for (const item of snapshot.items)
    next = appendFeedItem(next, item)

  return next
}

function appendFeedItem(state: AgentReducerState, item: BridgeFeedItem): AgentReducerState {
  if (item.kind === 'message')
    return appendMessage(state, item)

  return appendActivity(state, {
    activity: item.activity,
    badge: item.badge,
    title: item.title,
    detail: item.detail,
    text: item.text,
    lines: item.lines ?? [],
  })
}

function appendMessage(state: AgentReducerState, row: Omit<Extract<AgentRow, { kind: 'message' }>, 'id' | 'kind'>): AgentReducerState {
  return {
    ...state,
    rows: [...state.rows, { id: nextRowId(state), kind: 'message', ...row }],
  }
}

function completeMessageItem(
  state: AgentReducerState,
  event: Extract<AgentBridgeEvent, { type: 'message' }>,
): AgentReducerState {
  const active = state.activeAssistant
  if (active?.turnId == event.turnId && active.itemId == event.itemId)
    return updateMessageRow(
      { ...state, activeAssistant: null },
      active.rowId,
      row => ({
        ...row,
        tone: event.tone,
        text: event.text,
        phase: event.phase ?? row.phase,
      }),
    )

  return {
    ...appendMessage(state, {
      tone: event.tone,
      text: event.text,
      phase: event.phase,
    }),
    activeAssistant: null,
  }
}

function appendActivity(state: AgentReducerState, row: Omit<Extract<AgentRow, { kind: 'activity' }>, 'id' | 'kind'>): AgentReducerState {
  return {
    ...state,
    rows: [...state.rows, { id: nextRowId(state), kind: 'activity', ...row }],
    activeAssistant: null,
    shouldAutoScroll: true,
  }
}

function appendAssistantDelta(
  state: AgentReducerState,
  event: Extract<AgentBridgeEvent, { type: 'delta' }>,
): AgentReducerState {
  const active = state.activeAssistant
  if (active?.turnId == event.turnId && active.itemId == event.itemId)
    return updateMessageRow(state, active.rowId, row => ({
      ...row,
      text: row.text + event.delta,
    }))

  const next = appendMessage(state, { tone: 'assistant', text: event.delta })
  const rowId = next.rows.at(-1)?.id
  return rowId
    ? {
        ...next,
        activeAssistant: { turnId: event.turnId, itemId: event.itemId, rowId },
        shouldAutoScroll: true,
      }
    : next
}

function ensureAssistantCompletedText(state: AgentReducerState, text: string): AgentReducerState {
  if (hasAssistantText(state))
    return state
  const current = assistantRow(state)
  if (!current)
    return appendMessage(state, { tone: 'assistant', text, phase: 'final_answer' })
  return updateMessageRow(state, current.id, row => ({ ...row, text, phase: row.phase ?? 'final_answer' }))
}

function setAssistantMessage(state: AgentReducerState, text: string, tone: Extract<AgentRow, { kind: 'message' }>['tone']): AgentReducerState {
  const current = assistantRow(state)
  if (!current)
    return {
      ...appendMessage(state, { tone, text }),
      activeAssistant: null,
      shouldAutoScroll: true,
    }
  return updateMessageRow(
    { ...state, activeAssistant: null },
    current.id,
    row => ({
      ...row,
      tone,
      text,
    }),
  )
}

function assistantErrorText(state: AgentReducerState, error: string): string {
  const current = assistantText(state)
  return current ? `${current}\n\n${error}` : error
}

function assistantText(state: AgentReducerState): string {
  return assistantRow(state)?.text ?? ''
}

function assistantRow(state: AgentReducerState): Extract<AgentRow, { kind: 'message' }> | null {
  if (state.activeAssistant) {
    const active = state.rows.find(row => row.kind === 'message' && row.id === state.activeAssistant?.rowId)
    if (active?.kind === 'message')
      return active
  }

  const row = state.rows.at(-1)
  if (!row || row.kind !== 'message' || row.tone === 'user')
    return null
  return row
}

function updateMessageRow(
  state: AgentReducerState,
  rowId: string,
  update: (row: Extract<AgentRow, { kind: 'message' }>) => Extract<AgentRow, { kind: 'message' }>,
): AgentReducerState {
  const index = state.rows.findIndex(row => row.kind === 'message' && row.id === rowId)
  if (index < 0)
    return state

  const rows = [...state.rows]
  const row = rows[index]
  if (row.kind !== 'message')
    return state
  rows[index] = update(row)

  return {
    ...state,
    rows,
    shouldAutoScroll: true,
  }
}

function hasAssistantText(state: AgentReducerState): boolean {
  for (let index = state.rows.length - 1; index >= 0; index -= 1) {
    const row = state.rows[index]
    if (row.kind !== 'message')
      continue
    if (row.tone === 'user')
      return false
    if (row.text)
      return true
  }
  return false
}

function nextRowId(state: AgentReducerState): string {
  return String(state.rows.length + 1)
}

function makeConversationTitle(prompt: string): string {
  const collapsed = prompt
    .split(/\s+/)
    .filter(Boolean)
    .join(' ')
    .trim()

  if (!collapsed)
    return 'chat'
  if (collapsed.length <= 44)
    return collapsed
  return `${collapsed.slice(0, 43)}…`
}
