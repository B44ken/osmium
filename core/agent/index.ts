import config from '../config'
import { createInterface } from "node:readline"
import { chat, log, type Io } from "./proto"
import * as anthropic from "./anthropic"
import * as copilot from "./copilot"

const resume = process.argv[3] || undefined
const spec = process.argv[4] || config.agent.model   // resumed chats carry the spec they were created with
const provider = spec.split('/')[0]

const pending = new Map<string, (v: any) => void>()
let askId = 0
const ask: any = (o: any) => {
    const id = String(++askId)
    chat({ ...o, id })
    return new Promise(r => pending.set(id, r))
}
const io: Io = { chat, log, ask }

log("boot", { spec, cwd: process.cwd(), resume: resume ?? null, effort: config.agent.effort, perms: config.agent.permissions })

// two harnesses, not two providers: anthropic fronts claude/cohere/openrouter, copilot fronts the copilot sub
const backend = await (provider === 'copilot' ? copilot : anthropic).start({ spec, resume }, io)

createInterface({ input: process.stdin }).on("line", (line) => {
    const msg = JSON.parse(line)
    log("in", msg)
    if (msg.t === "say") backend.say(msg.text)
    if (msg.t === "perm") { pending.get(msg.id)!(msg.allow); pending.delete(msg.id) }
    if (msg.t === "answer") { pending.get(msg.id)!(msg.answers); pending.delete(msg.id) }
    if (msg.t === "stop") backend.stop()
})
