import type { ServerWebSocket, Subprocess } from "bun"
import type { msgIn, msgOut } from "../proto"
import { Chats, toolLine } from "./chats"
import type { Command, Row, State } from "./state"

export type Client = ServerWebSocket<{ session: Session; viewing: boolean }>
export class Session {
    state: State
    session = ''
    spec = ''
    clients = new Set<Client>()
    process!: Subprocess
    private ready = false
    private messageId?: string
    private queue: msgIn[] = []
    private saving = Promise.resolve()

    constructor(readonly id: string, readonly cwd: string, readonly chats: Chats) {
        this.state = { id, cwd, rows: [], buttonState: 'send', ask: null, askq: null, unseen: false }
    }

    async start(bridge: string) {
        const stored = await this.chats.load(this.id, this.cwd)
        if (stored) {
            this.session = stored.session; this.spec = stored.spec
            this.state.rows = stored.rows.map(row => ({ ...row, id: crypto.randomUUID() }))
        }
        const proc = this.process = Bun.spawn([process.execPath, bridge, this.cwd, this.session, this.spec], {
            cwd: this.cwd, stdin: 'ignore', stdout: 'ignore', stderr: 'pipe',
            ipc: (event: msgOut) => this.handle(event),
        })
        const stderr = (async () => {
            let tail = ''
            for await (const chunk of proc.stderr.pipeThrough(new TextDecoderStream())) {
                process.stderr.write(chunk)
                tail = (tail + chunk).slice(-64 * 1024) // keep recent diagnostics without retaining a whole chat's logs
            }
            return tail.trim()
        })()
        // drain stderr before reporting exit so the final error and stack aren't lost.
        Promise.all([proc.exited, stderr]).then(([code, details]) => {
            this.state.buttonState = 'send'
            this.row('error', [`agent exited (code ${code})`, details].filter(Boolean).join('\n\n'))
            this.publish()
        })
        return this
    }

    row(kind: Row['kind'], text: string) { this.state.rows.push({ id: crypto.randomUUID(), kind, text }) }
    publish() { for (const client of this.clients) client.send(JSON.stringify(this.state)) }

    command(command: Command, client: Client) {
        if (command.t === 'viewing') {
            client.data.viewing = command.active
            if (command.active) this.state.unseen = false
        } else {
            if (command.t === 'say') {
                this.row('user', command.text)
                this.state.buttonState = 'pending'
            }
            if (command.t === 'perm') this.state.ask = null
            if (command.t === 'answer' || command.t === 'cancel') this.state.askq = null
            const message: msgIn = command.t === 'cancel' ? { t: 'stop' } : command
            if (this.process.exitCode !== null) {
                this.state.buttonState = 'send'
                this.row('error', 'agent not running')
            } else if (this.ready) this.process.send(message)
            else this.queue.push(message)
        }
        this.publish()
    }

    private handle(event: msgOut) {
        switch (event.t) {
            case 'ready':
                this.ready = true
                for (const command of this.queue.splice(0)) this.process.send(command)
                break
            case 'session': this.session = event.id; this.spec = event.spec; break
            case 'reply': this.row('user', event.text); this.state.buttonState = 'pending'; break
            case 'delta': {
                this.state.buttonState = 'thinking'
                const text = event.think || event.response || ''
                if (!text) break
                const last = this.state.rows.at(-1)
                if (last?.kind === 'assistant' && (!event.id || this.messageId === event.id)) last.text += text
                else this.row('assistant', text)
                this.messageId = event.id
                break
            }
            case 'tool': this.state.buttonState = 'thinking'; this.row('tool', toolLine(event.name, event.input)); break
            case 'ask': this.state.ask = { id: event.id, name: event.name }; break
            case 'askq': this.state.buttonState = 'thinking'; this.state.askq = { id: event.id, title: event.title, questions: event.questions }; break
            case 'dismiss':
                if (this.state.ask?.id === event.id) this.state.ask = null
                if (this.state.askq?.id === event.id) this.state.askq = null
                break
            case 'end': {
                this.state.buttonState = 'send'
                if (![...this.clients].some(c => c.data.viewing)) this.state.unseen = true
                if (event.error) this.row('error', event.message ?? 'turn failed')
                const saved = { id: this.id, cwd: this.cwd, session: this.session, spec: this.spec, rows: structuredClone(this.state.rows) }
                this.saving = this.saving.then(() => this.chats.save(saved))
                break
            }
        }
        this.publish()
    }

    async close() {
        this.process.kill()
        await this.process.exited
        await this.saving
    }
}
