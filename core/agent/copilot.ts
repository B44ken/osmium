import config from '../config'
import { CopilotClient } from "@github/copilot-sdk"
import type { PermissionRequest, SessionConfigBase } from "@github/copilot-sdk"
import type { Start } from "./proto"

const ladder = ["none", "low", "medium", "high", "xhigh", "max"]

// osm.yaml sets one effort for every model but each model publishes its own ladder, so clamp
// to the nearest rung. leaving it undefined turns thinking off entirely rather than defaulting.
const effort = (supported?: string[]) => {
    if (!supported) return undefined
    const dist = (e: string) => Math.abs(ladder.indexOf(e) - ladder.indexOf(config.agent.effort))
    return supported.reduce((a, b) => dist(b) < dist(a) ? b : a)
}

// the app's permission bar only shows a short label, so pick the identifying field per request kind
const label = (r: PermissionRequest) => {
    switch (r.kind) {
        case "shell": return r.fullCommandText
        case "write": return r.fileName
        case "read": return r.path
        case "url": return r.url
        case "mcp": case "custom-tool": case "hook": return r.toolName
        case "memory": return `memory ${r.action}`
        case "extension-management": case "extension-permission-access": return r.extensionName
        case "factory": return r.name
    }
}

export const start: Start = async ({ spec, resume }, io) => {
    const model = spec.split('/')[1]!
    const client = new CopilotClient({ logLevel: "none", workingDirectory: process.cwd() })
    await client.start()

    const info = (await client.listModels()).find(m => m.id === model)
    const auto = config.agent.permissions == 'auto' || config.agent.permissions == 'bypass'

    const cfg: SessionConfigBase = {
        clientName: "osmium",
        model,
        workingDirectory: process.cwd(),
        streaming: true,   // enables assistant.message_delta / assistant.reasoning_delta
        reasoningEffort: effort(info?.supportedReasoningEfforts),
        onPermissionRequest: async (req) => {
            if (auto) return { kind: "approve-once" }
            const allow = await io.ask({ t: "ask", name: label(req), title: req.kind, input: req })
            return allow ? { kind: "approve-once", approvedInteractively: true } : { kind: "reject", feedback: "denied" }
        },
        onUserInputRequest: async (req) => {
            const answers = await io.ask({
                t: "askq",
                questions: [{ question: req.question, options: (req.choices ?? []).map(label => ({ label })) }],
            })
            return { answer: answers[req.question]!, wasFreeform: false }
        },
    }

    const session = resume ? await client.resumeSession(resume, cfg) : await client.createSession(cfg)
    io.chat({ t: "session", id: session.sessionId, spec })

    let failed = false
    session.on(ev => {
        if (!ev.type.endsWith("_delta")) io.log("ev", ev.type)
        switch (ev.type) {
            case "assistant.message_delta":   return io.chat({ t: "delta", response: ev.data.deltaContent })
            case "assistant.reasoning_delta": return io.chat({ t: "delta", think: ev.data.deltaContent })
            case "tool.execution_start":      return io.chat({ t: "tool", name: ev.data.toolName, input: ev.data.arguments })
            case "session.error":             failed = true; return
            case "session.idle":              io.chat({ t: "end", error: failed }); failed = false; return
        }
    })

    return {
        say: (text) => { session.send(text) },
        stop: () => { session.abort() },
    }
}
