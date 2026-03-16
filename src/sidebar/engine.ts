import { accessSync, constants, readdirSync, readFileSync, statSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'

export type SidebarMode = 'hidden' | 'tabsPeek' | 'picker'
export type SidebarThreadStatus = 'idle' | 'loading' | 'loaded'
export type SidebarPickerSource =
  | { kind: 'recentChats' }
  | { kind: 'files'; directory: string }

export type SidebarState = {
  mode: SidebarMode
  pickerQuery: string
  pickerSelectionIndex: number
  pickerSource: SidebarPickerSource | null
}

export type SidebarContext = {
  tabs: SidebarTab[]
  selectedTabId: string | null
  currentSurface: SidebarSurface
  recentThreadsStatus: SidebarThreadStatus
  recentThreads: SidebarRecentThread[]
}

export type SidebarTab = {
  id: string
  kind: 'agent' | 'terminal' | 'editor' | 'browser' | 'unknown'
  kindPrefix: string
  title: string
  currentThreadId?: string | null
}

export type SidebarSurface = {
  kind: 'agent' | 'terminal' | 'editor' | 'browser' | 'unknown'
  cwd: string
  threadId?: string | null
}

export type SidebarRecentThread = {
  threadId: string
  cwd: string
  title: string
  preview: string
  updatedAt: number
}

export type SidebarRow = {
  kind: 'tab' | 'info' | 'recentChat' | 'parentDirectory' | 'directory' | 'file'
  primaryText: string
  secondaryText?: string
  tabId?: string
  threadId?: string
  cwd?: string
  path?: string
  isActivatable: boolean
}

export type SidebarAction =
  | { type: 'togglePicker' }
  | { type: 'dismiss' }
  | { type: 'showTabsPeek' }
  | { type: 'hideTabsPeek' }
  | { type: 'surfaceChanged' }
  | { type: 'refresh' }
  | { type: 'cycleTabs'; delta: number }
  | { type: 'sidebarKey'; keyCode: number; key: string; modifiers: string[] }
  | { type: 'clickRow'; row: number }

export type SidebarIntent =
  | { type: 'selectTab'; tabId: string }
  | { type: 'replaceAgentThread'; threadId: string; cwd: string }
  | { type: 'openBrowser'; path: string }
  | { type: 'openEditor'; path: string }
  | { type: 'runExecutable'; path: string }
  | { type: 'openSystem'; path: string }

export type SidebarResponse = {
  state: SidebarState
  rows: SidebarRow[]
  selectionIndex: number
  intent?: SidebarIntent
}

export const initialSidebarState = (): SidebarState => ({
  mode: 'hidden',
  pickerQuery: '',
  pickerSelectionIndex: -1,
  pickerSource: null,
})

export function reduceSidebar(
  rawState: SidebarState | null | undefined,
  context: SidebarContext,
  action: SidebarAction,
): SidebarResponse {
  let state = rawState ?? initialSidebarState()
  let intent: SidebarIntent | undefined

  switch (action.type) {
    case 'togglePicker':
      state = state.mode === 'picker' ? initialSidebarState() : pickerStateForSurface(context.currentSurface)
      break
    case 'dismiss':
      state = initialSidebarState()
      break
    case 'showTabsPeek':
      if (state.mode !== 'picker')
        state = { ...state, mode: 'tabsPeek' }
      break
    case 'hideTabsPeek':
      if (state.mode === 'tabsPeek')
        state = { ...state, mode: 'hidden' }
      break
    case 'surfaceChanged':
      if (state.mode === 'picker')
        state = pickerStateForSurface(context.currentSurface)
      break
    case 'refresh':
      break
    case 'cycleTabs':
      intent = cycleTabIntent(context, action.delta) ?? intent
      break
    case 'clickRow': {
      const rows = buildRows(state, context)
      const row = rows[action.row]
      if (!row) break
      ;({ state, intent } = activateRow(state, context, row))
      break
    }
    case 'sidebarKey': {
      const rows = buildRows(state, context)
      ;({ state, intent } = handleSidebarKey(state, context, rows, action))
      break
    }
  }

  const rows = buildRows(state, context)
  const selectionIndex = selectionIndexForState(state, rows, context)
  return {
    state: { ...state, pickerSelectionIndex: selectionIndex },
    rows,
    selectionIndex,
    intent,
  }
}

function pickerStateForSurface(surface: SidebarSurface): SidebarState {
  return {
    mode: 'picker',
    pickerQuery: '',
    pickerSelectionIndex: -1,
    pickerSource: surface.kind === 'agent'
      ? { kind: 'recentChats' }
      : { kind: 'files', directory: surface.cwd },
  }
}

function buildRows(state: SidebarState, context: SidebarContext): SidebarRow[] {
  switch (state.mode) {
    case 'hidden':
      return []
    case 'tabsPeek':
      return context.tabs.map((tab) => ({
        kind: 'tab',
        primaryText: `${tab.kindPrefix} ${tab.title}`,
        tabId: tab.id,
        isActivatable: true,
      }))
    case 'picker':
      return buildPickerRows(state, context)
  }
}

function buildPickerRows(state: SidebarState, context: SidebarContext): SidebarRow[] {
  if (!state.pickerSource)
    return []

  if (state.pickerSource.kind === 'recentChats') {
    const entries = recentChatRows(context)
    return applyQuery(entries, state.pickerQuery)
  }

  const directory = state.pickerSource.directory
  const displayDirectory = directory.replace(os.homedir(), '~')
  try {
    const entries = [
      infoRow(displayDirectory),
      ...directoryRows(directory),
    ]
    return applyQuery(entries, state.pickerQuery)
  } catch {
    return [infoRow(displayDirectory), infoRow('could not read folder')]
  }
}

function recentChatRows(context: SidebarContext): SidebarRow[] {
  const header = infoRow('recent chats')
  if (context.recentThreadsStatus === 'loading' || context.recentThreadsStatus === 'idle')
    return [header, infoRow('loading chats…')]

  if (!context.recentThreads.length)
    return [header, infoRow('no recent chats')]

  return [
    header,
    ...context.recentThreads.map((thread) => ({
      kind: 'recentChat' as const,
      primaryText: thread.title,
      secondaryText: compactRelativeTimestamp(thread.updatedAt),
      threadId: thread.threadId,
      cwd: thread.cwd,
      isActivatable: true,
    })),
  ]
}

function directoryRows(directory: string): SidebarRow[] {
  const entries = readdirSync(directory, { withFileTypes: true })
    .map((entry) => {
      const entryPath = path.join(directory, entry.name)
      const isDirectory = entry.isDirectory()
      const kind: SidebarRow['kind'] = isDirectory ? 'directory' : 'file'
      return {
        isDirectory,
        name: entry.name,
        row: {
          kind,
          primaryText: isDirectory ? `${entry.name}/` : entry.name,
          path: entryPath,
          isActivatable: true,
        },
      }
    })
    .sort((left, right) => {
      if (left.isDirectory !== right.isDirectory)
        return left.isDirectory ? -1 : 1
      const leftLower = left.name.toLocaleLowerCase()
      const rightLower = right.name.toLocaleLowerCase()
      if (leftLower === rightLower)
        return left.name.localeCompare(right.name)
      return leftLower.localeCompare(rightLower)
    })
    .map((entry) => entry.row)

  if (directory === '/')
    return entries

  const parent = path.dirname(directory) || '/'
  return [
    {
      kind: 'parentDirectory',
      primaryText: '../',
      path: parent,
      isActivatable: true,
    },
    ...entries,
  ]
}

function applyQuery(rows: SidebarRow[], query: string): SidebarRow[] {
  const trimmed = query.trim().toLocaleLowerCase()
  if (!trimmed)
    return rows

  const matched = rows
    .filter((row) => row.isActivatable)
    .map((row, index) => ({ row, index, rank: rowRank(row, trimmed) }))
    .filter((entry) => entry.rank >= 0)
    .sort((left, right) => left.rank === right.rank ? left.index - right.index : left.rank - right.rank)
    .map((entry) => entry.row)

  return matched.length ? matched : [infoRow('no matches')]
}

function rowRank(row: SidebarRow, query: string): number {
  const primary = row.primaryText.toLocaleLowerCase()
  const secondary = row.secondaryText?.toLocaleLowerCase() ?? ''
  const extra = [row.cwd, row.path, row.threadId].filter(Boolean).join('\n').toLocaleLowerCase()
  const haystack = `${primary}\n${secondary}\n${extra}`
  if (primary.startsWith(query) || haystack.startsWith(query))
    return 0
  if (haystack.includes(query))
    return 1
  return -1
}

function selectionIndexForState(state: SidebarState, rows: SidebarRow[], context: SidebarContext): number {
  if (state.mode === 'tabsPeek')
    return context.tabs.findIndex((tab) => tab.id === context.selectedTabId)

  if (state.mode !== 'picker')
    return -1

  const activatableRows = rows.flatMap((row, index) => row.isActivatable ? [index] : [])
  if (!activatableRows.length)
    return -1

  if (activatableRows.includes(state.pickerSelectionIndex))
    return state.pickerSelectionIndex

  return activatableRows[0]
}

function handleSidebarKey(
  state: SidebarState,
  context: SidebarContext,
  rows: SidebarRow[],
  action: Extract<SidebarAction, { type: 'sidebarKey' }>,
): { state: SidebarState; intent?: SidebarIntent } {
  if (state.mode === 'tabsPeek')
    return handleTabsPeekKey(state, context, action)

  if (state.mode !== 'picker')
    return { state }

  switch (action.keyCode) {
    case 53:
      if (state.pickerQuery)
        return { state: { ...state, pickerQuery: '', pickerSelectionIndex: -1 } }
      return { state: initialSidebarState() }
    case 123:
      return { state: navigateToParentDirectory(state) }
    case 124:
    case 36:
    case 76:
      return activateSelectedRow(state, context, rows)
    case 125:
      return { state: moveSelection(state, rows, 1) }
    case 126:
      return { state: moveSelection(state, rows, -1) }
    case 51:
    case 117:
      return { state: { ...state, pickerQuery: state.pickerQuery.slice(0, -1), pickerSelectionIndex: -1 } }
  }

  if (!action.modifiers.length && action.key.length === 1 && !isControlCharacter(action.key))
    return { state: { ...state, pickerQuery: `${state.pickerQuery}${action.key.toLocaleLowerCase()}`, pickerSelectionIndex: -1 } }

  return { state }
}

function handleTabsPeekKey(
  state: SidebarState,
  context: SidebarContext,
  action: Extract<SidebarAction, { type: 'sidebarKey' }>,
): { state: SidebarState; intent?: SidebarIntent } {
  switch (action.keyCode) {
    case 53:
    case 36:
    case 76:
      return { state: { ...state, mode: 'hidden' } }
    case 125:
      return { state, intent: cycleTabIntent(context, 1) ?? undefined }
    case 126:
      return { state, intent: cycleTabIntent(context, -1) ?? undefined }
    default:
      return { state }
  }
}

function activateSelectedRow(
  state: SidebarState,
  context: SidebarContext,
  rows: SidebarRow[],
): { state: SidebarState; intent?: SidebarIntent } {
  const row = rows[state.pickerSelectionIndex]
  if (!row)
    return { state }
  return activateRow(state, context, row)
}

function activateRow(
  state: SidebarState,
  context: SidebarContext,
  row: SidebarRow,
): { state: SidebarState; intent?: SidebarIntent } {
  if (!row.isActivatable)
    return { state }

  switch (row.kind) {
    case 'tab':
      return { state: { ...state, mode: 'hidden' }, intent: { type: 'selectTab', tabId: row.tabId! } }
    case 'recentChat': {
      const existing = context.tabs.find((tab) => tab.kind === 'agent' && tab.currentThreadId === row.threadId)
      if (existing)
        return { state: { ...state, mode: 'hidden' }, intent: { type: 'selectTab', tabId: existing.id } }
      return { state: { ...state, mode: 'hidden' }, intent: { type: 'replaceAgentThread', threadId: row.threadId!, cwd: row.cwd! } }
    }
    case 'parentDirectory':
    case 'directory':
      return {
        state: {
          mode: 'picker',
          pickerQuery: '',
          pickerSelectionIndex: -1,
          pickerSource: { kind: 'files', directory: row.path! },
        },
      }
    case 'file':
      return { state: { ...state, mode: 'hidden' }, intent: fileIntent(row.path!) }
  }
}

function moveSelection(state: SidebarState, rows: SidebarRow[], delta: number): SidebarState {
  const activatableRows = rows.flatMap((row, index) => row.isActivatable ? [index] : [])
  if (!activatableRows.length)
    return state

  const current = activatableRows.indexOf(state.pickerSelectionIndex)
  const currentIndex = current >= 0 ? current : 0
  const nextIndex = (currentIndex + delta + activatableRows.length) % activatableRows.length
  return { ...state, pickerSelectionIndex: activatableRows[nextIndex] }
}

function navigateToParentDirectory(state: SidebarState): SidebarState {
  if (state.pickerSource?.kind !== 'files' || state.pickerSource.directory === '/')
    return state

  return {
    mode: 'picker',
    pickerQuery: '',
    pickerSelectionIndex: -1,
    pickerSource: {
      kind: 'files',
      directory: path.dirname(state.pickerSource.directory) || '/',
    },
  }
}

function cycleTabIntent(context: SidebarContext, delta: number): SidebarIntent | null {
  if (!context.tabs.length)
    return null
  const currentIndex = Math.max(0, context.tabs.findIndex((tab) => tab.id === context.selectedTabId))
  const nextIndex = (currentIndex + delta + context.tabs.length) % context.tabs.length
  return { type: 'selectTab', tabId: context.tabs[nextIndex].id }
}

function fileIntent(filePath: string): SidebarIntent {
  if (shouldOpenInBrowser(filePath))
    return { type: 'openBrowser', path: filePath }
  if (isLikelyTextFile(filePath))
    return { type: 'openEditor', path: filePath }
  if (isExecutableFile(filePath))
    return { type: 'runExecutable', path: filePath }
  return { type: 'openSystem', path: filePath }
}

function shouldOpenInBrowser(filePath: string): boolean {
  const ext = path.extname(filePath).toLocaleLowerCase()
  return ext === '.pdf' || ext === '.html' || ext === '.htm'
}

function isLikelyTextFile(filePath: string, sampleSize = 4096): boolean {
  try {
    const sample = readFileSync(filePath)
    const data = sample.subarray(0, sampleSize)
    if (!data.length)
      return true
    if (data.includes(0))
      return false
    const text = new TextDecoder('utf-8', { fatal: true }).decode(data)
    return text.length >= 0
  } catch {
    return false
  }
}

function isExecutableFile(filePath: string): boolean {
  try {
    accessSync(filePath, constants.X_OK)
    return !statSync(filePath).isDirectory()
  } catch {
    return false
  }
}

function infoRow(primaryText: string): SidebarRow {
  return {
    kind: 'info',
    primaryText,
    isActivatable: false,
  }
}

function compactRelativeTimestamp(updatedAt: number): string {
  const seconds = Math.max(0, Math.floor(Date.now() / 1000 - updatedAt))
  if (seconds < 60)
    return 'now'
  if (seconds < 3600)
    return `${Math.floor(seconds / 60)}m`
  if (seconds < 86400)
    return `${Math.floor(seconds / 3600)}h`
  if (seconds < 604800)
    return `${Math.floor(seconds / 86400)}d`
  if (seconds < 2592000)
    return `${Math.floor(seconds / 604800)}w`
  if (seconds < 31536000)
    return `${Math.floor(seconds / 2592000)}mo`
  return `${Math.floor(seconds / 31536000)}y`
}

function isControlCharacter(value: string): boolean {
  const code = value.codePointAt(0)
  return code === undefined || code < 32 || code === 127
}
