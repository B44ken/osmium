import config from '../config'
import { query } from "@anthropic-ai/claude-agent-sdk"
import type { Start } from "./proto"

// anthropic-wire harness: claude sub direct, cohere + openrouter (the catch-all, whose model ids are
// themselves `vendor/model`) via ANTHROPIC_BASE_URL
const route = (spec: string) => {
    const [provider, model] = spec.split('/')
    let args = { model, base: '', key: config.agent.keys[provider] || '' }
    if (provider == 'claude') {}
    else if (provider == 'cohere') args.base = 'https://api.cohere.com/v2/chat'
    else args = { model: spec, base: 'https://openrouter.ai/api', key: config.agent.keys.openrouter }
    return args
}

export const start: Start = async ({ spec, resume }, io) => {
    const { model, base, key } = route(spec)
    process.env.ANTHROPIC_BASE_URL = base
    process.env.ANTHROPIC_AUTH_TOKEN = key
    io.log("anthropic", { model, base, key: key ? "set" : "none" })

    let wake: ((m: any) => void) | null = null
    const queue: any[] = []
    const userMsg = (text: string) => ({ type: "user", message: { role: "user", content: text }, parent_tool_use_id: null })
    async function* prompts() { while (true) yield queue.length ? queue.shift() : await new Promise(r => (wake = r)) }

    let interrupting = false
    const q = query({
        prompt: prompts(), options: {
            cwd: process.cwd(), resume, includePartialMessages: true,
            effort: config.agent.effort, permissionMode: config.agent.permissions, model,
            canUseTool: async (name, input, { title }) => {
                if (name === "AskUserQuestion") {   // not a permission: collect the user's picks, feed them back as the tool result
                    const answers = await io.ask({ t: "askq", questions: (input as any).questions })
                    return { behavior: "allow", updatedInput: { ...(input as any), answers } }
                }
                if (config.agent.permissions == 'auto' || config.agent.permissions == 'bypass') return true
                const allow = await io.ask({ t: "ask", name, title: title ?? name, input })
                return allow ? { behavior: "allow", updatedInput: input } : { behavior: "deny", message: "denied" }
            }
        }
    })

    let announced = false
    ;(async () => {
        for await (const ev of q as any) {
            if (ev.type === "stream_event") io.log("ev", ev.event?.type)
            else io.log("ev", ev.type, ev.subtype ?? "")
            if (!announced && ev.session_id) { announced = true; io.chat({ t: "session", id: ev.session_id, spec }) }
            if (ev.type === "stream_event") {
                const delta = ev.event?.delta
                if (delta?.type === "text_delta" && typeof delta.text === "string") {
                    const key = ev.event?.content_block?.type == 'thinking' ? 'think' : 'response'
                    io.chat({ t: "delta", [key]: delta.text })
                }
            }
            if (ev.type === "assistant") {
                for (const b of ev.message?.content ?? [])
                    if (b.type === "tool_use") io.chat({ t: "tool", name: b.name, input: b.input })
            } else if (ev.type === "result") {
                io.chat({ t: "end", error: !interrupting && ev.subtype !== "success" })
                interrupting = false
            }
        }
    })()

    return {
        say: (text) => {
            const m = userMsg(text)
            if (wake) { const w = wake; wake = null; w(m) } else queue.push(m)
        },
        stop: () => { interrupting = true; q.interrupt() },
    }
}
