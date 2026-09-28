import type { Question, msgIn } from "../proto"

export type Row = { id: string; kind: "user" | "assistant" | "tool" | "error"; text: string }
export type PastChat = { id: string; title: string; cwd: string; updated: string }
export type State = {
    id: string; cwd: string; rows: Row[]
    buttonState: "send" | "pending" | "thinking"
    ask: { id: string; name: string } | null
    askq: { id: string; title?: string; questions: Question[] } | null
    unseen: boolean
}
export type Command = msgIn | { t: "viewing"; active: boolean } | { t: "cancel" }
export type Settings = {
    home: string; cwd: string; mono: string; size: number
    sidebar: { width: number; slidedelay: number; slideduration: number }
}
