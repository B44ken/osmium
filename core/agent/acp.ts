import { spawn } from 'node:child_process'
import { once } from 'node:events'
import { Readable, Writable } from 'node:stream'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as acp from '@agentclientprotocol/sdk'
import { z } from 'zod'
import config from '../config'
import type { Io, Question, Start } from './proto'

const agents = {
    claude: { package: 'claude-agent-acp', modes: { auto: 'auto', bypass: 'bypassPermissions', ask: 'default' } },
    codex: { package: 'codex-acp', modes: { auto: 'agent', bypass: 'agent-full-access', ask: 'read-only' } },
}
const ladder = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra']
type CodexMeta = {
    asyncUserInput?: { itemId: string, questions: { title: string, options: string[] | null }[] }
    threadStatus?: { type: string }
}

// both adapters express built-in questions and mcp forms as json schema.
export async function elicit(params: acp.CreateElicitationRequest, io: Io, signal: AbortSignal, provider: string): Promise<acp.CreateElicitationResponse> {
    if (!acp.CreateElicitationRequest.isForm(params)) throw new Error('unsupported elicitation mode')
    const properties = Object.entries(params.requestedSchema.properties ?? {})
    const questions: Question[] = properties.map(([id, field]) => {
        let options: Question['options'] = []
        if (acp.ElicitationPropertySchema.isString(field)) {
            options = field.oneOf?.map(o => ({ label: o.title, value: o.const, description: o.description ?? undefined }))
                ?? field.enum?.map(value => ({ label: value, value })) ?? []
        } else if (acp.ElicitationPropertySchema.isArray(field)) {
            options = acp.MultiSelectItems.isTitled(field.items)
                ? field.items.anyOf.map(o => ({ label: o.title, value: o.const, description: o.description ?? undefined }))
                : (field.items as acp.StringMultiSelectItems).enum.map(value => ({ label: value, value }))
        } else if (acp.ElicitationPropertySchema.isBoolean(field)) {
            options = [{ label: 'yes', value: 'true' }, { label: 'no', value: 'false' }]
        }
        return { id, question: String(field.title ?? id), header: field.description ? String(field.description) : undefined, options,
            multiSelect: field.type === 'array', required: params.requestedSchema.required?.includes(id) ?? false }
    })
    const answers = await io.ask({ t: 'askq', title: `${provider}: ${params.message}`, questions }, signal)
    if (answers === undefined) return { action: 'cancel' }
    if (answers === null) return { action: 'decline' }
    const content = Object.fromEntries(properties.filter(([id]) => answers[id]?.length).map(([id, field]) => {
        const answer = answers[id]!
        const values = typeof answer === 'string' ? [answer] : answer
        const value = field.type === 'array' ? values : field.type === 'boolean' ? values[0] === 'true'
            : field.type === 'number' || field.type === 'integer' ? Number(values[0]) : values[0]
        return [id, value]
    }))
    z.fromJSONSchema(params.requestedSchema as z.core.JSONSchema.JSONSchema).parse(content)
    return { action: 'accept', content }
}

export const start: Start = async ({ spec, resume }, io) => {
    const [provider, model] = spec.split('/')
    const agent = agents[provider as keyof typeof agents]
    if (!agent) throw new Error(`unsupported agent: ${provider}; use claude/model or codex/model`)
    const mode = agent.modes[config.agent.permissions as keyof typeof agent.modes]
    if (!mode) throw new Error('agent.permissions must be auto, ask, or bypass')
    const entry = join(dirname(fileURLToPath(import.meta.resolve(`@agentclientprotocol/${agent.package}/package.json`))), 'dist/index.js')
    const proc = spawn('node', [entry], { stdio: ['pipe', 'pipe', 'inherit'], cwd: process.cwd() })
    const exited = once(proc, 'exit')
    let closing = false
    let running = false, detached = false, threadStatus = ''
    let questions = new AbortController()
    proc.on('exit', (code, signal) => {
        if (!closing) throw new Error(`${provider} adapter exited (${signal ?? code})`)
    })
    const connection = acp.client({ name: 'osmium' })
        .onNotification(acp.methods.client.session.update, ({ params: { update } }) => {
            const meta = update._meta?.codex as CodexMeta | undefined
            if (meta?.asyncUserInput) {
                void askAsync(meta.asyncUserInput).catch(error => {
                    io.log('question error', String(error))
                    io.chat({ t: 'end', error: true, message: String(error) })
                })
                return
            }
            if (meta?.threadStatus) {
                threadStatus = meta.threadStatus.type
                if (detached && threadStatus === 'idle') {
                    detached = false
                    io.chat({ t: 'end', error: false })
                }
            }
            switch (update.sessionUpdate) {
                case 'agent_message_chunk':
                case 'agent_thought_chunk':
                    if (update.content.type === 'text') io.chat({ t: 'delta',
                        id: update.messageId ? `${update.sessionUpdate}:${update.messageId}` : undefined,
                        [update.sessionUpdate === 'agent_message_chunk' ? 'response' : 'think']: update.content.text })
                    break
                case 'tool_call': io.chat({ t: 'tool', name: update.name ?? update.kind ?? update.title, input: update.rawInput }); break
            }
        })
        .onRequest(acp.methods.client.session.requestPermission, async ({ params, signal }) => {
            const allow = await io.ask({ t: 'ask', name: params.toolCall.title ?? 'tool', input: params.toolCall.rawInput }, signal)
            if (allow === undefined) return { outcome: { outcome: 'cancelled' } }
            const option = params.options.find(o => o.kind === (allow ? 'allow_once' : 'reject_once'))!
            return { outcome: { outcome: 'selected', optionId: option.optionId } }
        })
        .onRequest(acp.methods.client.elicitation.create, ({ params, signal }) => elicit(params, io, signal, provider!))
        .connect(acp.ndJsonStream(Writable.toWeb(proc.stdin), Readable.toWeb(proc.stdout) as unknown as ReadableStream<Uint8Array>))
    const remote = connection.agent
    let sessionId: string
    const say = async (text: string) => {
        const params: acp.PromptRequest = { sessionId, prompt: [{ type: 'text', text }] }
        if (running) {
            const result = await remote.request<{ outcome: string }>('_session/steering', params)
            if (result.outcome === 'failed') throw new Error('could not deliver the answer')
            if (result.outcome === 'startedNewTurn') {
                detached = threadStatus !== 'idle'
                if (!detached) io.chat({ t: 'end', error: false })
            }
            return
        }
        running = true
        try {
            const result = await remote.request(acp.methods.agent.session.prompt, params)
            io.chat({ t: 'end', error: result.stopReason !== 'end_turn' && result.stopReason !== 'cancelled', message: result.stopReason })
        } finally { running = false }
    }
    const askAsync = async (request: NonNullable<CodexMeta['asyncUserInput']>) => {
        const fields = request.questions.map((q, i) => ({ id: String(i), question: q.title,
            options: (q.options ?? []).map(value => ({ label: value, value })), required: true, freeform: true }))
        const answers = await io.ask({ t: 'askq', title: 'codex', questions: fields }, questions.signal)
        if (answers === undefined) return
        const text = fields.map(q => `${q.question}\n${answers === null ? '(skipped)' : [answers[q.id]].flat().join(', ')}`).join('\n\n')
        io.chat({ t: 'reply', text })
        await say(text)
    }
    try {
        await remote.request(acp.methods.agent.initialize, {
            protocolVersion: acp.PROTOCOL_VERSION, clientInfo: { name: 'osmium', version: '0.1' },
            clientCapabilities: { elicitation: { form: {} } },
        })
        const params: acp.NewSessionRequest = { cwd: process.cwd(), mcpServers: [] }
        const session = resume
            ? { ...await remote.request(acp.methods.agent.session.resume, { ...params, sessionId: resume }), sessionId: resume }
            : await remote.request(acp.methods.agent.session.new, params)
        sessionId = session.sessionId
        let options = session.configOptions!
        const set = async (configId: string, value: string) => {
            options = (await remote.request(acp.methods.agent.session.setConfigOption, { sessionId, configId, value })).configOptions
        }
        await set('model', model!)
        await set('mode', mode)
        const effort = options.find(o => o.category === 'thought_level')
        if (effort?.type === 'select') {
            const values = effort.options.flatMap(o => 'options' in o ? o.options : [o]).map(o => o.value)
            const supported = values.filter(v => ladder.includes(v))
            const distance = (v: string) => Math.abs(ladder.indexOf(v) - ladder.indexOf(config.agent.effort))
            await set(effort.id, values.includes(config.agent.effort) ? config.agent.effort
                : supported.reduce((a, b) => distance(b) < distance(a) ? b : a))
        }
        io.chat({ t: 'session', id: sessionId, spec })
        return {
            say,
            stop: () => {
                questions.abort(); questions = new AbortController()
                return remote.notify(acp.methods.agent.session.cancel, { sessionId })
            },
            close: async () => {
                closing = true
                questions.abort()
                try { await remote.request(acp.methods.agent.session.close, { sessionId }) }
                finally { proc.stdin.end(); await exited; connection.close() }
            },
        }
    } catch (error) {
        closing = true
        proc.stdin.end()
        await exited
        connection.close()
        throw error
    }
}
