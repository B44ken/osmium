import { spawn, type ChildProcess } from 'node:child_process'
import { accessSync, constants, readdirSync } from 'node:fs'
import os from 'node:os'
import { delimiter, dirname, join } from 'node:path'
import readline from 'node:readline'

type Json = null | boolean | number | string | Json[] | { [key: string]: Json }
type JsonObject = { [key: string]: Json }
type ApprovalPolicy = 'untrusted' | 'on-failure' | 'on-request' | 'never'
type SandboxMode = 'read-only' | 'workspace-write' | 'danger-full-access'

type JsonRpcRequest = { id: number, method: string, params?: unknown }
type JsonRpcSuccess = { id: number, result: unknown }
type JsonRpcFailure = { id: number, error: { code: number, message: string, data?: unknown } }
type JsonRpcNotification = { method: string, params?: unknown }

type TransportEvent = { kind: 'notification'; message: JsonRpcNotification } | { kind: 'closed'; error: Error }
type PendingRequest = { method: string, resolve: (value: unknown) => void, reject: (error: Error) => void }
type CodexAccountResponse = {
    account: null | { type: 'apiKey' } | { type: 'chatgpt'; email: string; planType: ChatGPTPlan }
    requiresOpenaiAuth: boolean
}
type CodexModel = {
    model: string
    displayName: string
    hidden: boolean
    isDefault: boolean
}
type CodexModelListResponse = { data: CodexModel[] }

type CodexThreadStartResponse = { thread: { id: string } }
type CodexThreadResumeResponse = { thread: { id: string } }
type CodexTurnStartResponse = { turn: { id: string } }
type CodexTurn = { id: string, status: ChatGPTTurnStatus, error: null | { message: string } }
type CodexThreadItem = JsonObject & { type: string, id: string, text?: string }
type CodexTurnStartedNotification = { threadId: string, turn: CodexTurn }

type CodexTurnCompletedNotification = {
    threadId: string
    turn: CodexTurn
}

type CodexItemCompletedNotification = {
    threadId: string
    turnId: string
    item: CodexThreadItem
}

type CodexAgentMessageDeltaNotification = {
    threadId: string
    turnId: string
    itemId: string
    delta: string
}

type CodexSandboxPolicy =
    | { type: 'dangerFullAccess' }
    | { type: 'readOnly'; access: { type: 'fullAccess' }; networkAccess: boolean }
    | {
        type: 'workspaceWrite'
        writableRoots: string[]
        readOnlyAccess: { type: 'fullAccess' }
        networkAccess: boolean
        excludeTmpdirEnvVar: boolean
        excludeSlashTmp: boolean
    }

type CodexNormalizedInput =
    | { type: 'text'; text: string; text_elements: [] }
    | { type: 'localImage'; path: string }

export type ChatGPTPlan =
    | 'free'
    | 'go'
    | 'plus'
    | 'pro'
    | 'team'
    | 'business'
    | 'enterprise'
    | 'edu'
    | 'unknown'

export type ChatGPTTurnStatus = 'completed' | 'interrupted' | 'failed' | 'inProgress'
export type ChatGPTReasoningEffort = 'low' | 'medium' | 'high' | 'xhigh'

export type ChatGPTInputItem =
    | { type: 'text'; text: string }
    | { type: 'local_image'; path: string }

export type ChatGPTInput = string | ChatGPTInputItem[]

export type ChatGPTThreadItem = CodexThreadItem

export type ChatGPTTurnResult = {
    threadId: string
    turnId: string
    text: string
    status: ChatGPTTurnStatus
    error?: string
    items: ChatGPTThreadItem[]
}

export type ChatGPTStreamEvent =
    | { type: 'thread.started'; threadId: string }
    | { type: 'thread.resumed'; threadId: string }
    | { type: 'turn.started'; threadId: string; turnId: string }
    | { type: 'delta'; threadId: string; turnId: string; itemId: string; delta: string }
    | { type: 'item.completed'; threadId: string; turnId: string; item: ChatGPTThreadItem }
    | { type: 'completed'; result: ChatGPTTurnResult }

export type ChatGPTModelOption = {
    model: string
    displayName: string
    isDefault: boolean
}

export type ChatGPTClientOptions = {
    codexPath?: string
    cwd?: string
    model?: string
    approvalPolicy?: ApprovalPolicy
    sandbox?: SandboxMode
}

export type ChatGPTRunOptions = {
    cwd?: string
    model?: string
    threadId?: string
    previousResponseId?: string
    newThread?: boolean
    effort?: ChatGPTReasoningEffort
}

export class ChatGPTClient {
    readonly defaultCwd: string
    readonly defaultModel?: string
    readonly approvalPolicy: ApprovalPolicy
    readonly sandbox: SandboxMode

    private readonly transport: AppServerTransport
    private currentThreadId: string | null = null
    private activeTurn = false

    private constructor(transport: AppServerTransport, defaultCwd: string, defaultModel?: string, approvalPolicy: ApprovalPolicy = 'never', sandbox: SandboxMode = 'read-only') {
        this.transport = transport
        this.defaultCwd = defaultCwd
        this.defaultModel = defaultModel
        this.approvalPolicy = approvalPolicy
        this.sandbox = sandbox
    }

    static async create(options: ChatGPTClientOptions = {}): Promise<ChatGPTClient> {
        const cwd = options.cwd ?? process.cwd()
        const transport = AppServerTransport.spawn(resolveCodexPath(options.codexPath), cwd)

        try {
            await transport.request('initialize', {
                clientInfo:  { name: 'osmium', title: 'Osmium', version: '0.1.0' },
                capabilities: null,
            })
            transport.notify('initialized')

            const account = await transport.request<CodexAccountResponse>('account/read', {
                refreshToken: false,
            })

            if (!account.account || account.account.type !== 'chatgpt') {
                await transport.close()
                throw new Error(
                    account.requiresOpenaiAuth
                        ? 'codex app-server is not logged into ChatGPT; run `codex login` first'
                        : 'codex app-server is not using ChatGPT auth'
                )
            }

            return new ChatGPTClient(
                transport,
                cwd,
                options.model,
                options.approvalPolicy ?? 'never',
                options.sandbox ?? 'read-only',
            )
        } catch (error) {
            await transport.close()
            throw error
        }
    }

    async listModels(limit = 9): Promise<ChatGPTModelOption[]> {
        const response = await this.transport.request<CodexModelListResponse>('model/list', {
            limit,
            includeHidden: false,
        })
        return response.data
            .filter((model) => !model.hidden)
            .map((model) => ({
                model: model.model,
                displayName: model.displayName,
                isDefault: model.isDefault,
            }))
    }

    async *stream(input: ChatGPTInput, options: ChatGPTRunOptions = {}): AsyncGenerator<ChatGPTStreamEvent> {
        if (this.activeTurn)
            throw new Error('only one active turn is supported per ChatGPTClient')
        this.activeTurn = true

        const queue = new AsyncQueue<ChatGPTStreamEvent>()
        const items: ChatGPTThreadItem[] = []
        const thread = await this.ensureThread(options)
        let turnId: string | null = null
        let started = false
        let text = ''

        queue.push({ type: thread.kind, threadId: thread.threadId })

        const bindTurn = (candidate?: string) => {
            if (!candidate) return false
            if (!turnId) turnId = candidate
            return turnId === candidate
        }

        const startTurn = () => {
            if (started || !turnId) return
            started = true
            queue.push({ type: 'turn.started', threadId: thread.threadId, turnId })
        }

        const unsubscribe = this.transport.subscribe(event => {
            if (event.kind === 'closed') {
                queue.fail(event.error)
                return
            }

            const message = event.message
            switch (message.method) {
                case 'turn/started': {
                    const params = message.params as CodexTurnStartedNotification
                    if (params.threadId !== thread.threadId || !bindTurn(params.turn.id)) return
                    startTurn()
                    break
                }
                case 'item/agentMessage/delta': {
                    const params = message.params as CodexAgentMessageDeltaNotification
                    if (params.threadId !== thread.threadId || !bindTurn(params.turnId)) return
                    if (!turnId) return
                    startTurn()
                    text += params.delta
                    queue.push({
                        type: 'delta',
                        threadId: thread.threadId,
                        turnId,
                        itemId: params.itemId,
                        delta: params.delta,
                    })
                    break
                }
                case 'item/completed': {
                    const params = message.params as CodexItemCompletedNotification
                    if (params.threadId !== thread.threadId || !bindTurn(params.turnId)) return
                    if (!turnId) return
                    items.push(params.item)
                    if (params.item.type === 'agentMessage' && typeof params.item.text === 'string')
                        text = params.item.text
                    queue.push({
                        type: 'item.completed',
                        threadId: thread.threadId,
                        turnId,
                        item: params.item,
                    })
                    break
                }
                case 'turn/completed': {
                    const params = message.params as CodexTurnCompletedNotification
                    if (params.threadId !== thread.threadId || !bindTurn(params.turn.id)) return
                    if (!turnId) return
                    queue.push({
                        type: 'completed',
                        result: {
                            threadId: thread.threadId,
                            turnId,
                            text,
                            status: params.turn.status,
                            error: params.turn.error?.message,
                            items: [...items],
                        },
                    })
                    queue.end()
                    break
                }
            }
        })

        try {
            const startedTurn = await this.transport.request<CodexTurnStartResponse>('turn/start', {
                threadId: thread.threadId,
                input: normalizeInput(input),
                cwd: options.cwd ?? this.defaultCwd,
                approvalPolicy: this.approvalPolicy,
                sandboxPolicy: mapSandboxPolicy(this.sandbox, options.cwd ?? this.defaultCwd),
                model: options.model ?? this.defaultModel ?? null,
                effort: options.effort ?? null,
            })
            bindTurn(startedTurn.turn.id)
            startTurn()

            for await (const event of queue)
                yield event
        } finally {
            unsubscribe()
            this.activeTurn = false
        }
    }

    async close(): Promise<void> {
        await this.transport.close()
    }

    private async ensureThread(options: ChatGPTRunOptions): Promise<{ kind: 'thread.started' | 'thread.resumed'; threadId: string }> {
        const requestedThreadId = options.newThread ? undefined : options.threadId ?? options.previousResponseId ?? this.currentThreadId ?? undefined
        const cwd = options.cwd ?? this.defaultCwd
        const model = options.model ?? this.defaultModel ?? null

        if (!requestedThreadId) {
            const response = await this.transport.request<CodexThreadStartResponse>('thread/start', {
                model,
                modelProvider: null,
                serviceTier: null,
                cwd,
                approvalPolicy: this.approvalPolicy,
                sandbox: this.sandbox,
                config: null,
                serviceName: 'osmium',
                baseInstructions: null,
                developerInstructions: null,
                personality: 'pragmatic',
                ephemeral: false,
                experimentalRawEvents: false,
                persistExtendedHistory: false,
            })
            this.currentThreadId = response.thread.id
            return { kind: 'thread.started', threadId: response.thread.id }
        }

        if (this.currentThreadId === requestedThreadId)
            return { kind: 'thread.resumed', threadId: requestedThreadId }

        const response = await this.transport.request<CodexThreadResumeResponse>('thread/resume', {
            threadId: requestedThreadId,
            history: null,
            path: null,
            model,
            modelProvider: null,
            serviceTier: null,
            cwd,
            approvalPolicy: this.approvalPolicy,
            sandbox: this.sandbox,
            config: null,
            baseInstructions: null,
            developerInstructions: null,
            personality: 'pragmatic',
            persistExtendedHistory: false,
        })
        this.currentThreadId = response.thread.id
        return { kind: 'thread.resumed', threadId: response.thread.id }
    }
}

class AppServerTransport {
    private readonly child: ChildProcess
    private readonly stderrTail: string[] = []
    private readonly pending = new Map<number, PendingRequest>()
    private readonly subscribers = new Set<(event: TransportEvent) => void>()
    private nextId = 1
    private closed = false

    private constructor(child: ChildProcess) {
        this.child = child
        this.attach()
    }

    static spawn(codexPath: string, cwd: string): AppServerTransport {
        const nodePath = resolveNodePath(codexPath)
        const useNode = !!nodePath && codexPath.startsWith('/')
        const child = spawn(useNode ? nodePath : codexPath, useNode ? [codexPath, 'app-server'] : ['app-server'], {
            cwd,
            env: process.env,
            stdio: ['pipe', 'pipe', 'pipe'],
        })

        if (!child.stdin || !child.stdout || !child.stderr)
            throw new Error('codex app-server did not expose stdio pipes')

        return new AppServerTransport(child)
    }

    async request<T>(method: string, params?: unknown): Promise<T> {
        const id = this.nextId++
        const request: JsonRpcRequest = params === undefined ? { id, method } : { id, method, params }

        const promise = new Promise<T>((resolve, reject) => {
            this.pending.set(id, {
                method,
                resolve: (value) => resolve(value as T),
                reject,
            })
        })

        this.write(request)
        return await promise
    }

    notify(method: string, params?: unknown): void {
        this.write(params === undefined ? { method } : { method, params })
    }

    subscribe(listener: (event: TransportEvent) => void): () => void {
        this.subscribers.add(listener)
        return () => this.subscribers.delete(listener)
    }

    async close(): Promise<void> {
        if (this.closed) return
        this.handleClose(new Error('codex app-server client closed'))
        this.child.stdin?.end()
        this.child.kill()
    }

    private write(message: JsonRpcRequest | JsonRpcNotification): void {
        if (this.closed)
            throw new Error('codex app-server client is closed')
        if (!this.child.stdin?.writable)
            throw new Error(`codex app-server is unavailable${formatStderrTail(this.stderrTail)}`)
        this.child.stdin.write(`${JSON.stringify(message)}\n`)
    }

    private attach(): void {
        if (!this.child.stdout || !this.child.stderr)
            throw new Error('codex app-server stdio is unavailable')

        const out = readline.createInterface({ input: this.child.stdout })
        const err = readline.createInterface({ input: this.child.stderr })

        out.on('line', (line) => this.handleStdoutLine(line))
        err.on('line', (line) => this.captureStderr(line))

        this.child.once('error', (error) => this.handleClose(error))
        this.child.once('exit', (code, signal) => {
            const detail = code !== null ? `exit code ${code}` : `signal ${signal ?? 'unknown'}`
            this.handleClose(new Error(`codex app-server exited with ${detail}${formatStderrTail(this.stderrTail)}`))
        })
    }

    private handleStdoutLine(line: string): void {
        if (!line.trim()) return

        let message: JsonRpcSuccess | JsonRpcFailure | JsonRpcNotification
        try {
            message = JSON.parse(line) as JsonRpcSuccess | JsonRpcFailure | JsonRpcNotification
        } catch {
            this.captureStderr(`non-json app-server output: ${line}`)
            return
        }

        if ('id' in message) {
            const pending = this.pending.get(message.id)
            if (!pending) return
            this.pending.delete(message.id)
            if ('error' in message)
                pending.reject(new Error(`${pending.method} failed: ${message.error.message}`))
            else
                pending.resolve(message.result)
            return
        }

        for (const subscriber of this.subscribers)
            subscriber({ kind: 'notification', message })
    }

    private captureStderr(line: string): void {
        if (!line) return
        this.stderrTail.push(line)
        if (this.stderrTail.length > 40)
            this.stderrTail.splice(0, this.stderrTail.length - 40)
    }

    private handleClose(error: Error): void {
        if (this.closed) return
        this.closed = true
        for (const [id, pending] of this.pending) {
            this.pending.delete(id)
            pending.reject(error)
        }
        for (const subscriber of this.subscribers)
            subscriber({ kind: 'closed', error })
        this.subscribers.clear()
    }
}

class AsyncQueue<T> implements AsyncIterable<T>, AsyncIterator<T> {
    private readonly values: T[] = []
    private readonly waiters: Array<{
        resolve: (result: IteratorResult<T>) => void
        reject: (error: Error) => void
    }> = []
    private done = false
    private failure: Error | null = null

    push(value: T): void {
        if (this.done || this.failure) return
        const waiter = this.waiters.shift()
        if (waiter) waiter.resolve({ done: false, value })
        else this.values.push(value)
    }

    end(): void {
        if (this.done || this.failure) return
        this.done = true
        while (this.waiters.length)
            this.waiters.shift()!.resolve({ done: true, value: undefined as never })
    }

    fail(error: Error): void {
        if (this.failure || this.done) return
        this.failure = error
        this.values.length = 0
        while (this.waiters.length)
            this.waiters.shift()!.reject(error)
    }

    async next(): Promise<IteratorResult<T>> {
        if (this.values.length)
            return { done: false, value: this.values.shift()! }
        if (this.failure)
            throw this.failure
        if (this.done)
            return { done: true, value: undefined as never }

        return await new Promise<IteratorResult<T>>((resolve, reject) => {
            this.waiters.push({ resolve, reject })
        })
    }

    async return(): Promise<IteratorResult<T>> {
        this.end()
        return { done: true, value: undefined as never }
    }

    [Symbol.asyncIterator](): AsyncIterator<T> {
        return this
    }
}

function normalizeInput(input: ChatGPTInput): CodexNormalizedInput[] {
    if (typeof input === 'string')
        return [{ type: 'text', text: input, text_elements: [] }]

    return input.map((item) => item.type === 'text'
        ? { type: 'text', text: item.text, text_elements: [] }
        : { type: 'localImage', path: item.path })
}

function mapSandboxPolicy(
    sandbox: SandboxMode,
    cwd: string,
): CodexSandboxPolicy {
    switch (sandbox) {
        case 'danger-full-access':
            return { type: 'dangerFullAccess' }
        case 'workspace-write':
            return {
                type: 'workspaceWrite',
                writableRoots: [cwd],
                readOnlyAccess: { type: 'fullAccess' },
                networkAccess: false,
                excludeTmpdirEnvVar: false,
                excludeSlashTmp: false,
            }
        case 'read-only':
        default:
            return {
                type: 'readOnly',
                access: { type: 'fullAccess' },
                networkAccess: false,
            }
    }
}

function resolveCodexPath(explicit?: string): string {
    return explicit
        ?? process.env.CODEX
        ?? resolveCommand('codex')
        ?? resolveHomeCommand('codex')
        ?? 'codex'
}

function resolveNodePath(codexPath: string): string | undefined {
    return process.env.NODE
        ?? resolveCommand('node')
        ?? (codexPath.startsWith('/') ? executable(join(dirname(codexPath), 'node')) : undefined)
        ?? resolveHomeCommand('node')
}

function resolveCommand(name: string): string | undefined {
    const suffixes = process.platform === 'win32' ? ['', '.exe', '.cmd'] : ['']

    for (const dir of (process.env.PATH ?? '').split(delimiter).filter(Boolean))
        for (const suffix of suffixes) {
            const file = executable(join(dir, name + suffix))
            if (file) return file
        }
}

function resolveHomeCommand(name: string): string | undefined {
    const home = os.homedir()
    const nvm = join(home, '.nvm', 'versions', 'node')

    try {
        for (const version of readdirSync(nvm).sort().reverse()) {
            const file = executable(join(nvm, version, 'bin', name))
            if (file) return file
        }
    } catch {}

    return executable(join(home, '.volta', 'bin', name))
        ?? executable(join(home, '.local', 'bin', name))
        ?? executable(join(home, 'bin', name))
}

function executable(file: string): string | undefined {
    try {
        accessSync(file, constants.X_OK)
        return file
    } catch {}
}

function formatStderrTail(lines: string[]): string {
    if (!lines.length) return ''
    return `\nstderr:\n${lines.join('\n')}`
}
