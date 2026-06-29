import config from '../../osm.yaml'
import { query } from "@anthropic-ai/claude-agent-sdk"
import { createInterface } from "node:readline"
import { writeSync } from "node:fs"

type msgOut = { t: "delta", think?: string, response?: string } | { t: "tool", name: string, input: any } | { t: "end", error: boolean } | { t: "ask", id: string, name: string, title?: string, input: any } | { t: "askq", id: string, questions: any }
const log = (...a: any[]) => { writeSync(2, `[bridge ${new Date().toISOString()}] ${a.map(x => typeof x === "string" ? x : JSON.stringify(x)).join(" ")}\n`) }
const chat = (o: msgOut) => { if (o.t !== "delta") log("out", o); writeSync(1, JSON.stringify(o) + "\n") }

const route = (path: string) => {
  const [provider, model] = path.split('/')
  let args = { model, base: '', key: config.keys[provider] || '' }
  if (provider == 'claude') {}
  else if (provider == 'cohere') args.base = 'https://api.cohere.com/v2/chat'
  else args = {...args, model: path }
  return args
}
const { model, base, key } = route(config.agent.model)
process.env.ANTHROPIC_BASE_URL = base!
process.env.ANTHROPIC_AUTH_TOKEN = key!

log("boot", { model, base, cwd: process.cwd(), resume: process.argv[3] ?? null, effort: config.agent.effort, perms: config.agent.permissions })

let wake: ((m: any) => void) | null = null
const queue: any[] = []
const userMsg = (text: string) => ({ type: "user", message: { role: "user", content: text }, parent_tool_use_id: null })
function say(text: string) {
    const m = userMsg(text)
    if (wake) { const w = wake; wake = null; w(m) } else queue.push(m)
}
async function* prompts() { while (true) yield queue.length ? queue.shift() : await new Promise(r => (wake = r)) }

const pending = new Map<string, (v: any) => void>()
let permId = 0
let interrupting = false

createInterface({ input: process.stdin }).on("line", (line) => {
    const msg = JSON.parse(line)
    log("in", msg)
    if (msg.t === "say") say(msg.text)
    if (msg.t === "perm") { pending.get(msg.id)?.(msg.allow); pending.delete(msg.id) }
    if (msg.t === "answer") { pending.get(msg.id)?.(msg.answers); pending.delete(msg.id) }
    if (msg.t === "stop") { interrupting = true; q.interrupt() }
})

const q = query({
    prompt: prompts(), options: {
        cwd: process.cwd(), resume: process.argv[3], includePartialMessages: true,
        effort: config.agent.effort, permissionMode: config.agent.permissions, model,
        canUseTool: async (name, input, { title }) => {
            if (name === "AskUserQuestion") {   // not a permission: collect the user's picks, feed them back as the tool result
                const id = String(++permId)
                chat({ t: "askq", id, questions: (input as any).questions })
                const answers = await new Promise<any>(r => pending.set(id, r))
                return { behavior: "allow", updatedInput: { ...(input as any), answers } }
            }
            if(config.agent.permissions == 'auto' ||  config.agent.permissions == 'bypass') return true
            const id = String(++permId)
            chat({ t: "ask", id, name, title: title ?? name, input })
            const allow = await new Promise<boolean>(r => pending.set(id, r))
            return allow ? { behavior: "allow", updatedInput: input } : { behavior: "deny", message: "denied" }
        }
    }
})

for await (const ev of q as any) {
    if (ev.type === "stream_event") log("ev", ev.event?.type)
    else log("ev", ev.type, ev.subtype ?? "")
    if (ev.type === "stream_event") {
        const delta = ev.event?.delta
        if (delta?.type === "text_delta" && typeof delta.text === "string") {
            const key = ev.event?.content_block?.type == 'thinking' ? 'think' : 'response'
            chat({ t: "delta", [key]: delta.text })
        }
    }
    if (ev.type === "assistant") {
        for (const b of ev.message?.content ?? [])
          if (b.type === "tool_use") chat({ t: "tool", name: b.name, input: b.input })
    } else if (ev.type === "result") {
        chat({ t: "end", error: !interrupting && ev.subtype !== "success" })
        interrupting = false
    }
}
