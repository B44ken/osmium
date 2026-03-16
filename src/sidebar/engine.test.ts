import { afterEach, describe, expect, test } from 'bun:test'
import { chmodSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {
  initialSidebarState,
  reduceSidebar,
  type SidebarContext,
  type SidebarSurface,
  type SidebarTab,
} from './engine.ts'

const tempRoots: string[] = []

describe('sidebar engine', () => {
  afterEach(() => {
    while (tempRoots.length)
      rmSync(tempRoots.pop()!, { recursive: true, force: true })
  })

  test('tabs peek rows mirror tabs and select the active tab', () => {
    const response = reduceSidebar(
      initialSidebarState(),
      context({
        tabs: [
          tab({ id: 'tab-1', kindPrefix: 'tt', title: 'one' }),
          tab({ id: 'tab-2', kindPrefix: 'ag', title: 'two' }),
        ],
        selectedTabId: 'tab-2',
      }),
      { type: 'showTabsPeek' },
    )

    expect(response.state.mode).toBe('tabsPeek')
    expect(response.rows.map((row) => row.primaryText)).toEqual(['tt one', 'ag two'])
    expect(response.selectionIndex).toBe(1)
  })

  test('agent picker shows recent chats and reuses an open tab when thread already exists', () => {
    const response = reduceSidebar(
      initialSidebarState(),
      context({
        currentSurface: surface({ kind: 'agent', cwd: '/tmp/chat', threadId: 'thread-open' }),
        recentThreadsStatus: 'loaded',
        recentThreads: [
          recentThread({ threadId: 'thread-open', title: 'open chat', updatedAt: nowSeconds() - 7200 }),
          recentThread({ threadId: 'thread-new', title: 'new chat', updatedAt: nowSeconds() - 120 }),
        ],
        tabs: [
          tab({ id: 'agent-open', kind: 'agent', currentThreadId: 'thread-open', kindPrefix: 'ag', title: 'open chat' }),
        ],
      }),
      { type: 'togglePicker' },
    )

    expect(response.state.mode).toBe('picker')
    expect(response.rows.map((row) => row.primaryText)).toEqual(['recent chats', 'open chat', 'new chat'])

    const activated = reduceSidebar(
      response.state,
      context({
        currentSurface: surface({ kind: 'agent', cwd: '/tmp/chat', threadId: 'thread-open' }),
        recentThreadsStatus: 'loaded',
        recentThreads: [
          recentThread({ threadId: 'thread-open', title: 'open chat', updatedAt: nowSeconds() - 7200 }),
          recentThread({ threadId: 'thread-new', title: 'new chat', updatedAt: nowSeconds() - 120 }),
        ],
        tabs: [
          tab({ id: 'agent-open', kind: 'agent', currentThreadId: 'thread-open', kindPrefix: 'ag', title: 'open chat' }),
        ],
      }),
      { type: 'clickRow', row: 1 },
    )

    expect(activated.intent).toEqual({ type: 'selectTab', tabId: 'agent-open' })
    expect(activated.state.mode).toBe('hidden')
  })

  test('file picker sorts directories first and navigates into a selected directory', () => {
    const root = tempDir()
    mkdirSync(path.join(root, 'beta'))
    mkdirSync(path.join(root, 'alpha'))
    writeFileSync(path.join(root, 'zeta.txt'), 'z')
    writeFileSync(path.join(root, 'aardvark.txt'), 'a')

    const opened = reduceSidebar(
      initialSidebarState(),
      context({ currentSurface: surface({ kind: 'editor', cwd: root }) }),
      { type: 'togglePicker' },
    )

    expect(opened.rows.map((row) => row.primaryText)).toEqual([
      root.replace(os.homedir(), '~'),
      '../',
      'alpha/',
      'beta/',
      'aardvark.txt',
      'zeta.txt',
    ])

    const navigated = reduceSidebar(
      opened.state,
      context({ currentSurface: surface({ kind: 'editor', cwd: root }) }),
      { type: 'clickRow', row: 2 },
    )

    expect(navigated.state.pickerSource).toEqual({ kind: 'files', directory: path.join(root, 'alpha') })
    expect(navigated.state.pickerQuery).toBe('')
  })

  test('picker typing filters with prefix-first ranking and escape clears then closes', () => {
    const root = tempDir()
    writeFileSync(path.join(root, 'late.txt'), 'a')
    writeFileSync(path.join(root, 'texfile.txt'), 'a')
    writeFileSync(path.join(root, 'notes.txt'), 'a')

    const opened = reduceSidebar(
      initialSidebarState(),
      context({ currentSurface: surface({ kind: 'editor', cwd: root }) }),
      { type: 'togglePicker' },
    )

    const typedT = reduceSidebar(opened.state, context({ currentSurface: surface({ kind: 'editor', cwd: root }) }), key('t'))
    const typedTe = reduceSidebar(typedT.state, context({ currentSurface: surface({ kind: 'editor', cwd: root }) }), key('e'))

    expect(typedTe.rows.map((row) => row.primaryText)).toEqual(['texfile.txt', 'late.txt', 'notes.txt'])
    expect(typedTe.selectionIndex).toBe(0)

    const cleared = reduceSidebar(typedTe.state, context({ currentSurface: surface({ kind: 'editor', cwd: root }) }), esc())
    expect(cleared.state.mode).toBe('picker')
    expect(cleared.state.pickerQuery).toBe('')

    const closed = reduceSidebar(cleared.state, context({ currentSurface: surface({ kind: 'editor', cwd: root }) }), esc())
    expect(closed.state.mode).toBe('hidden')
  })

  test('file activation prefers browser for html and pdf, editor for text, terminal for executables', () => {
    const root = tempDir()
    const htmlPath = path.join(root, 'index.html')
    const pdfPath = path.join(root, 'doc.pdf')
    const textPath = path.join(root, 'note.txt')
    const execPath = path.join(root, 'tool.bin')
    const blobPath = path.join(root, 'blob.bin')

    writeFileSync(htmlPath, '<html></html>')
    writeFileSync(pdfPath, '%PDF-1.7')
    writeFileSync(textPath, 'hello')
    writeFileSync(execPath, Buffer.from([0x7f, 0x45, 0x4c, 0x46, 0x00]))
    writeFileSync(blobPath, Buffer.from([0x00, 0xff, 0x10]))
    chmodSync(execPath, 0o755)

    expect(fileIntentFor(root, 'index.html')).toEqual({ type: 'openBrowser', path: htmlPath })
    expect(fileIntentFor(root, 'doc.pdf')).toEqual({ type: 'openBrowser', path: pdfPath })
    expect(fileIntentFor(root, 'note.txt')).toEqual({ type: 'openEditor', path: textPath })
    expect(fileIntentFor(root, 'tool.bin')).toEqual({ type: 'runExecutable', path: execPath })
    expect(fileIntentFor(root, 'blob.bin')).toEqual({ type: 'openSystem', path: blobPath })
  })
})

const key = (value: string) => ({ type: 'sidebarKey' as const, keyCode: 0, key: value, modifiers: [] })
const esc = () => ({ type: 'sidebarKey' as const, keyCode: 53, key: '', modifiers: [] })

const fileIntentFor = (directory: string, name: string) => {
  const opened = reduceSidebar(
    initialSidebarState(),
    context({ currentSurface: surface({ kind: 'editor', cwd: directory }) }),
    { type: 'togglePicker' },
  )
  const row = opened.rows.findIndex((entry) => entry.primaryText === name)
  return reduceSidebar(
    opened.state,
    context({ currentSurface: surface({ kind: 'editor', cwd: directory }) }),
    { type: 'clickRow', row },
  ).intent
}

const tempDir = () => {
  const root = path.join(os.tmpdir(), `osmium-sidebar-${Date.now()}-${Math.random().toString(36).slice(2)}`)
  mkdirSync(root, { recursive: true })
  tempRoots.push(root)
  return root
}

const nowSeconds = () => Math.floor(Date.now() / 1000)

const tab = (overrides: Partial<SidebarTab> = {}): SidebarTab => ({
  id: overrides.id ?? 'tab-1',
  kind: overrides.kind ?? 'editor',
  kindPrefix: overrides.kindPrefix ?? 'ed',
  title: overrides.title ?? 'title',
  currentThreadId: overrides.currentThreadId ?? null,
})

const surface = (overrides: Partial<SidebarSurface> = {}): SidebarSurface => ({
  kind: overrides.kind ?? 'editor',
  cwd: overrides.cwd ?? '/tmp',
  threadId: overrides.threadId ?? null,
})

const recentThread = (overrides: Partial<SidebarContext['recentThreads'][number]> = {}) => ({
  threadId: overrides.threadId ?? 'thread-1',
  cwd: overrides.cwd ?? '/tmp/chat',
  title: overrides.title ?? 'chat',
  preview: overrides.preview ?? '',
  updatedAt: overrides.updatedAt ?? nowSeconds() - 60,
})

const context = (overrides: Partial<SidebarContext> = {}): SidebarContext => ({
  tabs: overrides.tabs ?? [tab()],
  selectedTabId: overrides.selectedTabId ?? (overrides.tabs?.[0]?.id ?? 'tab-1'),
  currentSurface: overrides.currentSurface ?? surface(),
  recentThreadsStatus: overrides.recentThreadsStatus ?? 'idle',
  recentThreads: overrides.recentThreads ?? [],
})
