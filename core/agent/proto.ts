import { writeSync } from "node:fs"

export type msgOut =
    | { t: "ready" }
    | { t: "dismiss", id: string }
    | { t: "reply", text: string }
    | { t: "delta", id?: string, think?: string, response?: string }
    | { t: "tool", name: string, input: any }
    | { t: "end", error: boolean, message?: string }
    | { t: "ask", id: string, name: string, title?: string, input: any }
    | { t: "askq", id: string, title?: string, questions: Question[] }
    | { t: "session", id: string, spec: string }   // native session id, so the app can resume this chat later

export const log = (...a: any[]) => { writeSync(2, `[bridge ${new Date().toISOString()}] ${a.map(x => typeof x === "string" ? x : JSON.stringify(x)).join(" ")}\n`) }
export const chat = (o: msgOut) => {
    if (o.t !== "delta") log("out", o)
    if (process.send) process.send(o)
    else writeSync(1, JSON.stringify(o) + "\n")
}

export type msgIn =
    | { t: "say", text: string }
    | { t: "stop" }
    | { t: "perm", id: string, allow: boolean }
    | { t: "answer", id: string, answers: Answers }

export type Question = { id?: string, question: string, header?: string, options: { label: string, value?: string, description?: string }[], multiSelect?: boolean, required?: boolean, freeform?: boolean }
export type Answers = Record<string, string | string[]> | null | undefined // decline / cancel
export type Ask = {
    (o: { t: "ask", name: string, title?: string, input: any }, signal: AbortSignal): Promise<boolean | undefined>
    (o: { t: "askq", title?: string, questions: Question[] }, signal: AbortSignal): Promise<Answers>
}

export type Io = { chat: typeof chat, log: typeof log, ask: Ask }
export type Backend = { say: (text: string) => Promise<void>, stop: () => Promise<void>, close: () => Promise<void> }
export type Start = (opts: { spec: string, resume?: string }, io: Io) => Promise<Backend>
