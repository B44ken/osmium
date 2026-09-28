import { expect, test } from 'bun:test'
import { elicit } from './acp'
import type { Io, Question } from './proto'
import type { CreateElicitationRequest } from '@agentclientprotocol/sdk'

const form: CreateElicitationRequest = {
    mode: 'form', sessionId: 'test', message: 'choose the settings',
    requestedSchema: {
        type: 'object', required: ['choice', 'many', 'enabled', 'count'],
        properties: {
            choice: { type: 'string', title: 'which color?', description: 'color', oneOf: [{ const: 'violet', title: 'violet label' }] },
            many: { type: 'array', items: { anyOf: [{ const: 'a, b', title: 'first' }, { const: 'c', title: 'second' }] } },
            enabled: { type: 'boolean' }, count: { type: 'integer', minimum: 0 },
            note: { type: 'string' }, omitted: { type: 'string' },
        },
    },
}

test('form fields retain ids, labels, arrays, free text, and scalar types', async () => {
    let questions: Question[] = []
    const io = { ask: async (request: any) => {
        expect(request.title).toBe('codex: choose the settings')
        questions = request.questions
        return { choice: ['violet'], many: ['a, b', 'c'], enabled: ['false'], count: ['0'], note: ['free text'] }
    } } as unknown as Io
    expect(await elicit(form, io, new AbortController().signal, 'codex')).toEqual({
        action: 'accept', content: { choice: 'violet', many: ['a, b', 'c'], enabled: false, count: 0, note: 'free text' },
    })
    expect(questions[0]).toMatchObject({ id: 'choice', question: 'which color?', header: 'color', required: true,
        options: [{ value: 'violet', label: 'violet label' }] })
    expect(questions.find(q => q.id === 'note')?.required).toBe(false)
})

test('declining and cancelling a form return distinct protocol actions', async () => {
    for (const [answer, action] of [[null, 'decline'], [undefined, 'cancel']] as const) {
        expect(await elicit(form, { ask: async () => answer } as unknown as Io, new AbortController().signal, 'codex')).toEqual({ action })
    }
})

test('invalid form answers surface a schema error', async () => {
    await expect(elicit(form, { ask: async () => ({ choice: ['not an option'] }) } as unknown as Io,
        new AbortController().signal, 'codex')).rejects.toThrow()
})
