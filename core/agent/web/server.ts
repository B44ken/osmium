import { homedir } from "node:os"
import { resolve } from "node:path"
import { load } from "../../config"
import { Chats, atomicWrite } from "./chats"
import { Session, type Client } from "./session"
import index from "./index.html"

export function serveAgent({ port = 7224, home = homedir(), bridge = resolve(import.meta.dir, '../index.ts') } = {}) {
    const chats = new Chats(home)
    const sessions = new Map<string, Promise<Session>>()
    const server = Bun.serve({
        hostname: '127.0.0.1', port,
        routes: { '/': index },
        async fetch(request, server) {
            const url = new URL(request.url)
            // agent commands are local; other websites must not drive this endpoint.
            const origin = request.headers.get('origin')
            const local = url.host === server.url.host || url.host === `localhost:${server.port}`
            if (!local || (origin && origin !== url.origin)) return new Response('forbidden', { status: 403 })
            if (url.pathname === '/health') return new Response('osmium agent')
            if (url.pathname === '/settings') {
                const { font, window } = load()
                return Response.json({ home, cwd: process.cwd(), mono: font.mono, size: font.sizes.agent ?? font.size, sidebar: window.sidebar })
            }
            if (url.pathname === '/font' && request.method === 'POST') {
                const { size } = await request.json()
                const file = Bun.file(`${home}/.osm/osm.yaml`)
                const config: any = await file.exists() ? Bun.YAML.parse(await file.text()) ?? {} : {}
                config.font ??= {}; config.font.sizes ??= {}
                config.font.sizes.agent = Math.min(48, Math.max(6, Math.round(size)))
                await atomicWrite(file.name!, Bun.YAML.stringify(config))
                return Response.json({ size: config.font.sizes.agent })
            }
            if (url.pathname === '/chats') return Response.json(await chats.list(url.searchParams.get('cwd') ?? process.cwd()))
            if (url.pathname === '/session') {
                const id = url.searchParams.get('id')!, cwd = chats.cwd(url.searchParams.get('cwd') ?? process.cwd())
                if (request.method === 'DELETE') {
                    const session = await sessions.get(id)
                    if (session) { sessions.delete(id); await session.close() }
                    return new Response(null, { status: 204 })
                }
                if (!sessions.has(id)) sessions.set(id, new Session(id, cwd, chats).start(bridge))
                const session = await sessions.get(id)!
                if (server.upgrade(request, { data: { session, viewing: false } })) return
                return new Response('websocket required', { status: 400 })
            }
            return new Response('not found', { status: 404 })
        },
        websocket: {
            open(client: Client) { client.data.session.clients.add(client); client.data.session.publish() },
            message(client: Client, message: string | Buffer) { client.data.session.command(JSON.parse(message.toString()), client) },
            close(client: Client) { client.data.session.clients.delete(client) },
        },
    })
    return { server, chats, sessions, async stop() {
        await Promise.all([...sessions.values()].map(async session => (await session).close()))
        await server.stop(true)
    } }
}

if (import.meta.main) {
    const app = serveAgent()
    console.log(`agent: ${app.server.url}`)
    process.on('SIGTERM', () => { void app.stop().then(() => process.exit(0)) })
    process.on('SIGINT', () => { void app.stop().then(() => process.exit(0)) })
}
