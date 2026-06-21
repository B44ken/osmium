import config from '../../osm.yaml'
import { query } from "@anthropic-ai/claude-agent-sdk"
import { createInterface } from "node:readline"
import { writeSync } from "node:fs"

type msgOut = { t: "delta", text: string } | { t: "tool", name: string, input: any } | { t: "end", error: boolean } | { t: "ask", id: string, name: string, title?: string, input: any }
const chat = (o: msgOut) => { writeSync(1, JSON.stringify(o) + "\n") }

const route = (model: string) => {
  if (model.startsWith('claudecode/'))
    return { model: model.split('claudecode/')[1], base: '', key: '' }
  else 
    return { model, base: 'https://openrouter.ai/api', key: config.keys.openrouter }
}

const { model, base, key } = route(config.agent.model)
process.env.ANTHROPIC_BASE_URL = base!
process.env.ANTHROPIC_AUTH_TOKEN = key!

let wake: ((m: any) => void) | null = null
const queue: any[] = []
const userMsg = (text: string) => ({ type: "user", message: { role: "user", content: text }, parent_tool_use_id: null })
function say(text: string) {
    const m = userMsg(text)
    if (wake) { const w = wake; wake = null; w(m) } else queue.push(m)
}
async function* prompts() { while (true) yield queue.length ? queue.shift() : await new Promise(r => (wake = r)) }

const pending = new Map<string, (allow: boolean) => void>()
let permId = 0
let interrupting = false

createInterface({ input: process.stdin }).on("line", (line) => {
    const msg = JSON.parse(line)
    if (msg.t === "say") say(msg.text)
    if (msg.t === "perm") { pending.get(msg.id)?.(msg.allow); pending.delete(msg.id) }
    if (msg.t === "stop") { interrupting = true; q.interrupt() }
})

const q = query({
    prompt: prompts(), options: {
        cwd: process.cwd(), resume: process.argv[3], includePartialMessages: true,
        effort: config.agent.effort, permissionMode: config.agent.permissions, model,
        canUseTool: async (name, input, { title }) => {
            const id = String(++permId)
            chat({ t: "ask", id, name, title: title ?? name, input })
            const allow = await new Promise<boolean>(r => pending.set(id, r))
            return allow ? { behavior: "allow", updatedInput: input } : { behavior: "deny", message: "denied" }
        }
    }
})

for await (const ev of q as any) {
    if (ev.type === "stream_event" && ev.event?.type === "content_block_delta" && ev.event.delta?.type === "text_delta")
        chat({ t: "delta", text: ev.event.delta.text })
    if (ev.type === "assistant")
        for (const b of ev.message?.content ?? [])
          if (b.type === "tool_use") chat({ t: "tool", name: b.name, input: b.input })
    else if (ev.type === "result") {
        chat({ t: "end", error: !interrupting && ev.subtype !== "success" })
        interrupting = false
    }
}
