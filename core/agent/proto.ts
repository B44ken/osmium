import { writeSync } from "node:fs"

export type msgOut =
    | { t: "delta", think?: string, response?: string }
    | { t: "tool", name: string, input: any }
    | { t: "end", error: boolean }
    | { t: "ask", id: string, name: string, title?: string, input: any }
    | { t: "askq", id: string, questions: any }
    | { t: "session", id: string, spec: string }   // native session id, so the app can resume this chat later

export const log = (...a: any[]) => { writeSync(2, `[bridge ${new Date().toISOString()}] ${a.map(x => typeof x === "string" ? x : JSON.stringify(x)).join(" ")}\n`) }
export const chat = (o: msgOut) => { if (o.t !== "delta") log("out", o); writeSync(1, JSON.stringify(o) + "\n") }

export type Question = { question: string, header?: string, options: { label: string, description?: string }[], multiSelect?: boolean }
export type Ask = {
    (o: { t: "ask", name: string, title?: string, input: any }): Promise<boolean>
    (o: { t: "askq", questions: Question[] }): Promise<Record<string, string>>
}

export type Io = { chat: typeof chat, log: typeof log, ask: Ask }
export type Backend = { say: (text: string) => void, stop: () => void }
export type Start = (opts: { spec: string, resume?: string }, io: Io) => Promise<Backend>
