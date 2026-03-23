import {
    CodexClient,
    type CodexModelOption,
    type CodexReasoningEffort,
    type CodexRecentThread,
    type CodexThreadSnapshot,
} from './usecodex.ts'
import { readConfig } from '../config.ts'

export type BridgeRecentThread = {
    threadId: string
    cwd: string
    title: string
    preview: string
    updatedAt: number
}

export type BridgeFeedItem =
    | { kind: 'message'; tone: 'assistant' | 'user' | 'status' | 'error'; text: string; phase?: 'commentary' | 'final_answer' }
    | { kind: 'activity'; activity: 'trace' | 'edit'; badge?: string; title: string; detail?: string; text?: string; lines?: string[] }

export type BridgeThreadSnapshot = {
    threadId: string
    cwd: string
    title: string
    items: BridgeFeedItem[]
}

export type AgentBridgeEvent =
    | { type: 'models'; models: CodexModelOption[] }
    | { type: 'threads'; threads: BridgeRecentThread[] }
    | { type: 'thread'; thread: BridgeThreadSnapshot }
    | { type: 'thread.started'; threadId: string }
    | { type: 'thread.resumed'; threadId: string }
    | { type: 'turn.started'; threadId: string; turnId: string }
    | { type: 'delta'; threadId: string; turnId: string; itemId: string; delta: string }
    | { type: 'message'; threadId: string; turnId: string; itemId?: string; tone: 'assistant' | 'user' | 'status' | 'error'; text: string; phase?: 'commentary' | 'final_answer' }
    | { type: 'trace'; threadId: string; turnId: string; badge?: string; title: string; detail?: string; text?: string; lines?: string[] }
    | { type: 'edit'; threadId: string; turnId: string; badge?: string; title: string; detail?: string; text?: string; lines?: string[] }
    | { type: 'completed'; threadId: string; turnId: string; text: string; error?: string }
    | { type: 'error'; message: string }

type ParsedArgs =
    | { mode: 'chat', cwd: string, prompt: string, threadId?: string, effort?: CodexReasoningEffort, model?: string }
    | { mode: 'models', cwd: string }
    | { mode: 'threads', cwd: string }
    | { mode: 'thread', cwd: string, threadId: string }

function parseArgs(argv: string[]): ParsedArgs {
    let cwd = process.cwd()
    let prompt = ''
    let threadId: string | undefined
    let effort: CodexReasoningEffort | undefined
    let model: string | undefined
    let mode: ParsedArgs['mode'] = 'chat'

    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i]
        if (arg == '--cwd') {
            cwd = argv[++i] ?? cwd
        } else if (arg == '--prompt') {
            prompt = argv[++i] ?? ''
        } else if (arg == '--thread-id') {
            threadId = argv[++i] ?? undefined
        } else if (arg == '--model') {
            model = argv[++i] ?? undefined
            continue
        } else if (arg == '--effort') {
            const value = argv[++i]
            if (value === 'low' || value === 'medium' || value === 'high' || value === 'xhigh')
                effort = value
            else throw new Error(`effort (${value}) should be low/medium/high/xhigh`)
        } else if (arg == '--list-models') {
            mode = 'models'
        } else if (arg == '--list-threads') {
            mode = 'threads'
        } else if (arg == '--read-thread') {
            threadId = argv[++i] ?? undefined
            mode = 'thread'
        } else throw new Error(`unknown argument: ${arg}`)
    }

    if (mode == 'models')
        return { mode: 'models', cwd }

    if (mode == 'threads')
        return { mode: 'threads', cwd }

    if (mode == 'thread') {
        if (!threadId)
            throw new Error('missing required --read-thread <threadId>')
        return { mode: 'thread', cwd, threadId }
    }

    if (!prompt.trim())
        throw new Error('missing required --prompt')

    return { mode: 'chat', cwd, prompt, threadId, effort, model }
}

const emit = (event: AgentBridgeEvent): void => { process.stdout.write(`${JSON.stringify(event)}\n`) }

const stringValue = (value: unknown): string | undefined =>
    typeof value == 'string' && value.trim() ? value.trim() : undefined

const numberValue = (value: unknown): number | undefined =>
    typeof value == 'number' && Number.isFinite(value) ? value : undefined

const stringArray = (value: unknown): string[] =>
    Array.isArray(value) ? value.filter((part): part is string => typeof part == 'string' && part.trim().length > 0) : []

const recordValue = (value: unknown): Record<string, unknown> | undefined =>
    value && typeof value == 'object' && !Array.isArray(value) ? value as Record<string, unknown> : undefined

function truncate(text: string | undefined, limit = 520): string | undefined {
    if (!text) return undefined
    if (text.length <= limit) return text
    return `${text.slice(0, limit - 1)}…`
}

const truncateToolText = (text: string | undefined) => truncate(text, 140)

function formatDuration(ms: number | undefined): string | undefined {
    if (ms === undefined) return undefined
    if (ms < 1000) return `${Math.round(ms)}ms`
    if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`
    if (ms < 60_000) return `${Math.round(ms / 1000)}s`
    return `${Math.round(ms / 60_000)}m`
}

function statusLabel(status: unknown): string | undefined {
    const value = stringValue(status)
    if (!value) return undefined
    if (value == 'inProgress') return 'running'
    return value.replace(/[A-Z]/g, (match) => ` ${match.toLowerCase()}`)
}

function stringifyJson(value: unknown): string | undefined {
    if (value === undefined || value === null) return undefined
    if (typeof value == 'string')
        return value
    try {
        return JSON.stringify(value)
    } catch {
        return undefined
    }
}

type FileChangeSummary = {
    adds: number
    deletes: number
    badge?: string
    title: string
    text: string
}

function fileChangeType(value: unknown): string | undefined {
    const kind = recordValue(value)
    return stringValue(kind?.type) ?? stringValue(value)
}

function fileChangeVerb(value: unknown): string {
    const type = fileChangeType(value)
    if (type == 'delete') return 'delete'
    if (type == 'update' && stringValue(recordValue(value)?.move_path)) return 'move'
    return 'write'
}

function diffStat(diff: string | undefined): { adds: number, deletes: number } {
    if (!diff) return { adds: 0, deletes: 0 }

    let adds = 0
    let deletes = 0
    for (const line of diff.split('\n')) {
        if (line.startsWith('+++') || line.startsWith('---')) continue
        if (line.startsWith('+')) adds += 1
        if (line.startsWith('-')) deletes += 1
    }
    return { adds, deletes }
}

function diffBadge(adds: number, deletes: number): string | undefined {
    if (!adds && !deletes) return undefined
    return `+${adds} -${deletes}`
}

function relativeDisplayPath(path: string, cwd: string | undefined): string {
    if (!cwd) return path
    if (path == cwd) return './'
    return path.startsWith(`${cwd}/`) ? `./${path.slice(cwd.length + 1)}` : path
}

function activityTitle(title: string, status: unknown): string {
    if (stringValue(status) != 'inProgress') return title
    switch (title) {
        case 'write':
            return 'writing'
        case 'delete':
            return 'deleting'
        case 'move':
            return 'moving'
        case 'command':
            return 'running'
        case 'tool call':
            return 'calling'
        default:
            return title
    }
}

function fileChangeSummaries(value: unknown, cwd: string | undefined): FileChangeSummary[] {
    if (!Array.isArray(value)) return []
    return value.flatMap(change => {
        const entry = recordValue(change)
        const path = stringValue(entry?.path)
        if (!path) return []

        const { adds, deletes } = diffStat(stringValue(entry?.diff))
        const badge = diffBadge(adds, deletes)
        const title = fileChangeVerb(entry?.kind)
        const text = relativeDisplayPath(path, cwd)
        return [{ adds, deletes, badge, title, text }]
    })
}

function contentItemText(value: unknown): string | undefined {
    if (!Array.isArray(value)) return undefined
    const text = value
        .map(item => recordValue(item))
        .flatMap(item => item?.type == 'inputText' ? [stringValue(item.text)] : [])
        .filter((part): part is string => !!part)
        .join('\n')
        .trim()
    return text || undefined
}

function detailLine(parts: Array<string | undefined>): string | undefined {
    const line = parts.filter((part): part is string => !!part).join(' · ')
    return line || undefined
}

function basename(path: string): string {
    const pieces = path.split('/').filter(Boolean)
    return pieces.at(-1) ?? path
}

async function readAgentDefaults(): Promise<{ model?: string; effort?: CodexReasoningEffort }> {
    const config = await readConfig()
    const agent = recordValue(config.agent)
    const model = stringValue(agent?.model)
    const thinking = stringValue(agent?.thinking)?.toLowerCase()
    const effort = thinking == 'low' || thinking == 'medium' || thinking == 'high' || thinking == 'xhigh'
        ? thinking
        : undefined
    return { model, effort }
}

function threadTitle(name: string | null | undefined, preview: string | undefined, cwd: string): string {
    const trimmedName = stringValue(name)
    if (trimmedName) return trimmedName
    const firstPreviewLine = preview
        ?.split('\n')
        .map(line => line.trim())
        .find(Boolean)
    return truncate(firstPreviewLine, 80) ?? basename(cwd)
}

function userInputText(value: unknown): string | undefined {
    if (!Array.isArray(value)) return undefined
    const text = value
        .map(part => recordValue(part))
        .flatMap(part => {
            switch (part?.type) {
                case 'text':
                    return [stringValue(part.text)]
                case 'image':
                    return ['[image]']
                case 'localImage':
                case 'local_image':
                    return ['[image]']
                case 'skill':
                    return [part.name ? `$${String(part.name)}` : '$skill']
                case 'mention':
                    return [part.name ? `@${String(part.name)}` : '@mention']
                default:
                    return []
            }
        })
        .filter((part): part is string => !!part)
        .join('\n')
        .trim()
    return text || undefined
}

function bridgeFeedItem(item: unknown, cwd?: string): BridgeFeedItem | null {
    const entry = recordValue(item)
    const type = stringValue(entry?.type)
    if (!entry || !type) return null

    switch (type) {
        case 'userMessage': {
            const text = userInputText(entry.content)
            return text ? { kind: 'message', tone: 'user', text } : null
        }
        case 'agentMessage': {
            const text = stringValue(entry.text)
            const phase = stringValue(entry.phase)
            return text
                ? { kind: 'message', tone: 'assistant', text, phase: phase == 'commentary' || phase == 'final_answer' ? phase : undefined }
                : null
        }
        case 'reasoning': {
            const summary = stringArray(entry.summary).join('\n')
            const content = stringArray(entry.content).join('\n')
            const text = truncate(summary || content)
            return text ? { kind: 'activity', activity: 'trace', title: 'thinking', text } : null
        }
        case 'plan': {
            const text = truncate(stringValue(entry.text))
            return text ? { kind: 'activity', activity: 'trace', title: 'plan', text } : null
        }
        case 'commandExecution': {
            const command = stringValue(entry.command) ?? 'command'
            return {
                kind: 'activity',
                activity: 'trace',
                title: activityTitle('command', entry.status),
                detail: detailLine([
                    statusLabel(entry.status),
                    formatDuration(numberValue(entry.durationMs)),
                    stringValue(entry.cwd),
                ]),
                text: truncateToolText(command),
            }
        }
        case 'mcpToolCall': {
            const name = [stringValue(entry.server), stringValue(entry.tool)].filter(Boolean).join('/')
            const error = stringValue(recordValue(entry.error)?.message) ?? stringValue(entry.error)
            return {
                kind: 'activity',
                activity: 'trace',
                title: activityTitle('tool call', entry.status),
                detail: detailLine([
                    name || undefined,
                    statusLabel(entry.status),
                    formatDuration(numberValue(entry.durationMs)),
                ]),
                text: truncateToolText(error ?? stringifyJson(entry.arguments) ?? stringifyJson(entry.result)),
            }
        }
        case 'dynamicToolCall': {
            const tool = stringValue(entry.tool)
            return {
                kind: 'activity',
                activity: 'trace',
                title: activityTitle('tool call', entry.status),
                detail: detailLine([
                    tool,
                    statusLabel(entry.status),
                    typeof entry.success == 'boolean' ? (entry.success ? 'ok' : 'failed') : undefined,
                    formatDuration(numberValue(entry.durationMs)),
                ]),
                text: truncateToolText(contentItemText(entry.contentItems) ?? stringifyJson(entry.arguments)),
            }
        }
        case 'webSearch': {
            const query = stringValue(entry.query)
            return query
                ? {
                    kind: 'activity',
                    activity: 'trace',
                    title: 'web search',
                    detail: statusLabel(entry.action),
                    text: truncate(query, 260),
                }
                : null
        }
        case 'fileChange': {
            const changes = fileChangeSummaries(entry.changes, cwd)
            if (!changes.length) return null
            const first = changes[0]
            const allSameTitle = changes.every(change => change.title == first.title)
            const title = changes.length == 1
                ? first.title
                : allSameTitle ? `${first.title} ${changes.length} files` : `${changes.length} files`
            const tail = changes.slice(1)
                .map(change => [change.badge ? `[${change.badge}]` : undefined, change.text].filter(Boolean).join(' '))
                .join(' ')
            return {
                kind: 'activity',
                activity: 'edit',
                badge: first.badge,
                title,
                detail: statusLabel(entry.status),
                text: [first.text, tail].filter(Boolean).join(' '),
                lines: changes.map(change => [change.badge ? `[${change.badge}]` : undefined, change.text].filter(Boolean).join(' ')).slice(0, 8),
            }
        }
        default:
            return null
    }
}

export const bridgeFeedItemForTest = bridgeFeedItem

function bridgeItemEvent(threadId: string, turnId: string, item: unknown, cwd?: string): AgentBridgeEvent | null {
    const normalized = bridgeFeedItem(item, cwd)
    if (!normalized) return null
    if (normalized.kind == 'message') {
        if (normalized.tone == 'user') return null
        return {
            type: 'message',
            threadId,
            turnId,
            itemId: stringValue(recordValue(item)?.id),
            tone: normalized.tone,
            text: normalized.text,
            phase: normalized.phase,
        }
    }
    return normalized.activity == 'trace'
        ? { type: 'trace', threadId, turnId, badge: normalized.badge, title: normalized.title, detail: normalized.detail, text: normalized.text, lines: normalized.lines }
        : { type: 'edit', threadId, turnId, badge: normalized.badge, title: normalized.title, detail: normalized.detail, text: normalized.text, lines: normalized.lines }
}

export const bridgeItemEventForTest = bridgeItemEvent

function bridgeRecentThreads(threads: CodexRecentThread[]): BridgeRecentThread[] {
    return threads.map((thread) => ({
        threadId: thread.threadId,
        cwd: thread.cwd,
        title: threadTitle(thread.name, thread.preview, thread.cwd),
        preview: truncate(thread.preview, 140) ?? '',
        updatedAt: thread.updatedAt,
    }))
}

function bridgeThreadSnapshot(thread: CodexThreadSnapshot): BridgeThreadSnapshot {
    const items: BridgeFeedItem[] = []
    for (const turn of thread.turns) {
        for (const item of turn.items) {
            const normalized = bridgeFeedItem(item, thread.cwd)
            if (normalized) items.push(normalized)
        }
        if (turn.status == 'failed' && turn.error) {
            items.push({ kind: 'message', tone: 'error', text: turn.error })
        } else if (turn.status == 'interrupted') {
            items.push({ kind: 'message', tone: 'status', text: 'Stopped.' })
        }
    }

    return {
        threadId: thread.threadId,
        cwd: thread.cwd,
        title: threadTitle(thread.name, thread.preview, thread.cwd),
        items,
    }
}

async function main(): Promise<void> {
    const args = parseArgs(process.argv.slice(2))
    const agentDefaults = await readAgentDefaults()
    const client = await CodexClient.create({
        cwd: args.cwd,
        codexPath: process.env.CODEX,
        sandbox: 'danger-full-access',
        model: agentDefaults.model,
        clientInfo: { name: 'osmium', title: 'Osmium', version: '0.1.0' },
    })

    try {
        if (args.mode === 'models') {
            emit({ type: 'models', models: await client.listModels(9) })
            return
        }

        if (args.mode === 'threads') {
            emit({ type: 'threads', threads: bridgeRecentThreads(await client.listThreads(40)) })
            return
        }

        if (args.mode === 'thread') {
            emit({ type: 'thread', thread: bridgeThreadSnapshot(await client.readThread(args.threadId)) })
            return
        }

        for await (const event of client.stream(args.prompt, {
            cwd: args.cwd,
            threadId: args.threadId,
            effort: args.effort ?? agentDefaults.effort,
            model: args.model ?? agentDefaults.model,
        })) {
            if(['thread.started', 'thread.resumed', 'turn.started', 'delta'].includes(event.type))
                emit(event as AgentBridgeEvent)
            else if(event.type == 'item.completed') {
                const itemEvent = bridgeItemEvent(event.threadId, event.turnId, event.item, args.cwd)
                if (itemEvent) emit(itemEvent)
            }
            else if(event.type == 'completed')
                emit({ type: 'completed', threadId: event.result.threadId, turnId: event.result.turnId, text: event.result.text, error: event.result.error })
            else
                continue
        }
    } finally { await client.close() }
}

if (import.meta.main) {
    main().catch((error) => {
        emit({ type: 'error', message: error instanceof Error ? error.message : String(error) })
        process.exitCode = 1
    })
}
