import { describe, expect, test } from 'bun:test'
import { initialAgentState, reduceAgent } from './reducer.ts'
import { bridgeFeedItemForTest, type BridgeFeedItem, type BridgeThreadSnapshot } from './bridge.ts'

describe('agent reducer', () => {
  test('submit sets title, appends user row, and marks busy', () => {
    const state = reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', {
      type: 'submit',
      prompt: '  hello world  ',
    })

    expect(state.title).toBe('hello world')
    expect(state.busy).toBe(true)
    expect(state.rows).toEqual([
      { id: '1', kind: 'message', tone: 'user', text: 'hello world' },
    ])
  })

  test('delta streaming creates and updates one assistant row', () => {
    const submitted = reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', {
      type: 'submit',
      prompt: 'hello',
    })

    const first = reduceAgent(submitted, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'delta', threadId: 't1', turnId: 'turn-1', itemId: 'item-1', delta: 'hi' },
    })
    const second = reduceAgent(first, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'delta', threadId: 't1', turnId: 'turn-1', itemId: 'item-1', delta: ' there' },
    })

    expect(second.rows.at(-1)).toEqual({ id: '2', kind: 'message', tone: 'assistant', text: 'hi there' })
    expect(second.rows.filter((row) => row.kind === 'message' && row.tone === 'assistant')).toHaveLength(1)
  })

  test('tool activity stays between assistant text segments', () => {
    const submitted = reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', {
      type: 'submit',
      prompt: 'hello',
    })

    const withIntro = reduceAgent(submitted, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'delta', threadId: 't1', turnId: 'turn-1', itemId: 'item-1', delta: 'first' },
    })
    const withTool = reduceAgent(withIntro, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'trace', threadId: 't1', turnId: 'turn-1', title: 'tool call', text: 'rg foo', lines: [] },
    })
    const withOutro = reduceAgent(withTool, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'delta', threadId: 't1', turnId: 'turn-1', itemId: 'item-1', delta: ' second' },
    })

    expect(withOutro.rows).toEqual([
      { id: '1', kind: 'message', tone: 'user', text: 'hello' },
      { id: '2', kind: 'message', tone: 'assistant', text: 'first' },
      { id: '3', kind: 'activity', activity: 'trace', title: 'tool call', detail: undefined, text: 'rg foo', lines: [] },
      { id: '4', kind: 'message', tone: 'assistant', text: ' second' },
    ])
  })

  test('tool activity text is capped to a short preview', async () => {
    const text = 'x'.repeat(300)
    const item = bridgeFeedItemForTest({ type: 'commandExecution', command: text, status: 'completed' }) as BridgeFeedItem

    expect(item.kind).toBe('activity')
    expect(item.text).toHaveLength(140)
    expect(item.text?.endsWith('…')).toBe(true)
  })

  test('completed with error turns the active assistant row into an error row', () => {
    const streamed = reduceAgent(
      reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', { type: 'submit', prompt: 'hello' }),
      '/tmp/demo',
      { type: 'bridgeEvent', event: { type: 'delta', threadId: 't1', turnId: 'turn-1', itemId: 'item-1', delta: 'partial' } },
    )

    const completed = reduceAgent(streamed, '/tmp/demo', {
      type: 'bridgeEvent',
      event: { type: 'completed', threadId: 't1', turnId: 'turn-1', text: '', error: 'boom' },
    })

    expect(completed.threadId).toBe('t1')
    expect(completed.rows.at(-1)).toEqual({
      id: '2',
      kind: 'message',
      tone: 'error',
      text: 'partial\n\nboom',
    })
  })

  test('cancelled exit appends stopped state', () => {
    const state = reduceAgent(
      reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', { type: 'submit', prompt: 'hello' }),
      '/tmp/demo',
      { type: 'turnExit', completed: false, cancelled: true, stderrText: null, terminationStatus: 0, terminationReason: 'exit' },
    )

    expect(state.busy).toBe(false)
    expect(state.rows.at(-1)).toEqual({ id: '2', kind: 'message', tone: 'status', text: 'Stopped.' })
  })

  test('replace thread loads snapshot rows and cwd', () => {
    const snapshot: BridgeThreadSnapshot = {
      threadId: 'thread-2',
      cwd: '/tmp/other',
      title: 'saved chat',
      items: [
        { kind: 'message', tone: 'user', text: 'hey' },
        { kind: 'activity', activity: 'trace', title: 'tool call', detail: 'ok', lines: ['write foo.ts'] },
      ],
    }

    const state = reduceAgent(initialAgentState('/tmp/demo'), '/tmp/demo', {
      type: 'replaceThread',
      snapshot,
    })

    expect(state.cwd).toBe('/tmp/other')
    expect(state.threadId).toBe('thread-2')
    expect(state.title).toBe('saved chat')
    expect(state.rows).toEqual([
      { id: '1', kind: 'message', tone: 'user', text: 'hey' },
      { id: '2', kind: 'activity', activity: 'trace', title: 'tool call', detail: 'ok', text: undefined, lines: ['write foo.ts'] },
    ])
  })
})
