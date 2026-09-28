import { rename } from "node:fs/promises"
import { resolve } from "node:path"
import type { PastChat, Row } from "./state"

export type Stored = PastChat & { session: string; spec: string; rows: Omit<Row, "id">[] }
export const toolLine = (name: string, input: Record<string, unknown> = {}) => {
    const preview = ["command", "file_path", "path", "pattern", "url", "query"]
        .map(key => input?.[key]).find(value => typeof value === "string") as string | undefined
    return Array.from(preview ? `[${name}] ${preview.replaceAll('\n', ' ')}` : name).slice(0, 120).join('')
}
export const atomicWrite = async (path: string, text: string) => {
    const temporary = `${path}.${crypto.randomUUID()}.tmp`
    await Bun.write(temporary, text)
    await rename(temporary, path)
}

// a fresh install has neither history directory; other filesystem errors still surface.
async function files(pattern: string) {
    try { return await Array.fromAsync(new Bun.Glob(pattern).scan()) }
    catch (error) { if ((error as NodeJS.ErrnoException).code === 'ENOENT') return []; throw error }
}

export class Chats {
    constructor(readonly home: string) {}
    cwd(path: string) { return resolve(path === '~' || !path ? this.home : path.startsWith('~/') ? `${this.home}/${path.slice(2)}` : path) }
    file(id: string) { return Bun.file(`${this.home}/.osm/chats/${id}.json`) }
    legacyDir(cwd: string) { return `${this.home}/.claude/projects/${this.cwd(cwd).replaceAll(/[/.]/g, '-')}` }

    async load(id: string, cwd: string): Promise<Stored | undefined> {
        if (await this.file(id).exists()) return this.file(id).json()
        const file = Bun.file(`${this.legacyDir(cwd)}/${id}.jsonl`)
        if (!await file.exists()) return
        const rows = legacyRows(await file.text())
        return { id, cwd: this.cwd(cwd), session: id, spec: 'claude/opus', title: rows.find(r => r.kind === 'user')?.text ?? '', updated: new Date(file.lastModified).toISOString(), rows }
    }

    async save(chat: Omit<Stored, 'title' | 'updated'>) {
        const first = chat.rows.find(r => r.kind === 'user')
        if (!first) return
        const stored: Stored = { ...chat, title: Array.from(first.text).slice(0, 80).join(''), updated: new Date().toISOString(), rows: chat.rows.map(({ kind, text }) => ({ kind, text })) }
        await atomicWrite(this.file(chat.id).name!, JSON.stringify(stored))
    }

    async list(cwd: string): Promise<PastChat[]> {
        const want = this.cwd(cwd)
        const ours: Stored[] = []
        for (const path of await files(`${this.home}/.osm/chats/*.json`)) {
            const chat: Stored = await Bun.file(path).json()
            if (chat.cwd === want) ours.push(chat)
        }
        const taken = new Set(ours.map(c => c.id))
        const past: PastChat[] = ours.map(({ id, title, cwd, updated }) => ({ id, title, cwd, updated }))
        for (const path of await files(`${this.legacyDir(want)}/*.jsonl`)) {
            const id = path.slice(path.lastIndexOf('/') + 1, -6)
            if (taken.has(id)) continue
            const file = Bun.file(path)
            const first = records(await file.slice(0, 128 << 10).text())
                .find(o => o.type === 'user' && messageText(o.message))
            if (first) past.push({ id, cwd: want, title: Array.from(messageText(first.message)!).slice(0, 80).join(''), updated: new Date(file.lastModified).toISOString() })
        }
        return past.sort((a, b) => b.updated.localeCompare(a.updated))
    }
}

// claude's legacy logs can contain partial final lines; native history skipped those too.
const records = (body: string): any[] => body.split('\n').flatMap(line => {
    try { return [JSON.parse(line)] } catch { return [] }
})
const messageText = (message: any): string | undefined => typeof message?.content === 'string'
    ? message.content || undefined
    : message?.content?.filter((b: any) => b.type === 'text').map((b: any) => b.text).join('\n') || undefined

function legacyRows(body: string): Omit<Row, 'id'>[] {
    return records(body).flatMap(o => {
        if (!['user', 'assistant'].includes(o.type) || !o.message) return []
        const kind = o.type as 'user' | 'assistant', content = o.message.content
        if (typeof content === 'string') return content ? [{ kind, text: content }] : []
        return (content ?? []).flatMap((b: any) => b.type === 'text' && b.text
            ? [{ kind, text: b.text }]
            : b.type === 'tool_use' ? [{ kind: 'tool', text: toolLine(b.name ?? 'tool', b.input) }] : [])
    })
}
