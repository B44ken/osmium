import config from '../config'
import { createInterface } from "node:readline"
import { chat, log, type Io, type msgIn } from "./proto"
import { start } from "./acp"

const resume = process.argv[3] || undefined
const spec = process.argv[4] || config.agent.model   // resumed chats carry the spec they were created with

const pending = new Map<string, (v: any) => void>()
let askId = 0
const ask: Io['ask'] = (o: any, signal: AbortSignal) => {
    const id = String(++askId)
    chat({ ...o, id })
    return new Promise<any>(resolve => {
        const cancel = () => finish(undefined)
        const finish = (value: any) => {
            pending.delete(id)
            signal.removeEventListener('abort', cancel)
            chat({ t: 'dismiss', id })
            resolve(value)
        }
        pending.set(id, finish)
        signal.addEventListener('abort', cancel, { once: true })
        if (signal.aborted) cancel()
    })
}
const io: Io = { chat, log, ask }

log("boot", { spec, cwd: process.cwd(), resume: resume ?? null, effort: config.agent.effort, perms: config.agent.permissions })

const backend = await start({ spec, resume }, io)
const fail = (error: unknown) => {
    log('error', String(error))
    chat({ t: 'end', error: true, message: String(error) })
}
const cancel = () => { for (const resolve of pending.values()) resolve(undefined) }
const close = async () => { cancel(); await backend.close() }

const handle = (msg: msgIn) => {
    log("in", msg)
    if (msg.t === "say") backend.say(msg.text).catch(fail)
    if (msg.t === "perm") pending.get(msg.id)?.(msg.allow)
    if (msg.t === "answer") pending.get(msg.id)?.(msg.answers)
    if (msg.t === "stop") { cancel(); backend.stop().catch(fail) }
}
if (process.send) { process.on("message", handle); process.on('disconnect', close) }
else createInterface({ input: process.stdin }).on("line", line => handle(JSON.parse(line))).on('close', close)
process.once('SIGTERM', async () => { await close(); process.exit(0) })
chat({ t: "ready" })
