/** @jsxImportSource preact */
import { render } from "preact"
import { useEffect, useLayoutEffect, useRef, useState } from "preact/hooks"
import { marked } from "marked"
import DOMPurify from "dompurify"
import type { Command, PastChat, Row, Settings, State } from "./state"

declare global {
    interface Window {
        osmActive: (active: boolean) => void
        osmFont: (size: number) => void
        webkit?: { messageHandlers: { agent?: { postMessage: (state: { busy: boolean; unseen: boolean } | { ready: true }) => void } } }
    }
}

const settings: Settings = await fetch('/settings').then(r => r.json())
const params = new URLSearchParams(location.search)
const embedded = params.get('embedded') === '1'
const initial = { id: params.get('id') ?? crypto.randomUUID(), cwd: params.get('cwd') ?? settings.cwd }
document.documentElement.classList.toggle('embedded', embedded)
document.documentElement.style.setProperty('--mono', JSON.stringify(settings.mono))
document.documentElement.style.setProperty('--sidebar-width', `${settings.sidebar.width}px`)
document.documentElement.style.setProperty('--slide-duration', `${settings.sidebar.slideduration}s`)
const setFont = (size: number) => document.documentElement.style.setProperty('--agent-size', `${size}px`)
setFont(settings.size)
window.osmFont = setFont

const escapeHTML = (text: string) => { const span = document.createElement('span'); span.textContent = text; return span.innerHTML }
marked.use({ renderer: {
    html: ({ text }) => escapeHTML(text),
    image: ({ text }) => escapeHTML(text),
} })

function RowView({ row }: { row: Row }) {
    if (row.kind === 'tool') {
        const half = Math.ceil(row.text.length / 2)
        return <div class="row tool" aria-label={row.text}><span class="tool-start">{row.text.slice(0, half)}</span><span class="tool-end"><span>{row.text.slice(half)}</span></span></div>
    }
    if (row.kind === 'assistant') return <div class="row assistant" onClick={event => {
        const link = (event.target as Element).closest('a')
        if (link && !embedded) { event.preventDefault(); window.open(link.href, '_blank', 'noopener,noreferrer') }
    }} dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(marked.parseInline(row.text, { async: false })) }} />
    return <div class={`row ${row.kind}`}>{row.text}</div>
}

function Questions({ ask, send }: { ask: NonNullable<State['askq']>; send: (command: Command) => void }) {
    const [picks, setPicks] = useState<Record<string, string[]>>({})
    const complete = ask.questions.every(q => q.required === false || picks[q.id ?? q.question]?.length)
    const toggle = (question: string, label: string, multi = false) => setPicks(old => {
        const selected = old[question] ?? []
        return { ...old, [question]: !multi ? [label] : selected.includes(label) ? selected.filter(v => v !== label) : [...selected, label] }
    })
    return <form class="questions bar" onSubmit={event => {
        event.preventDefault()
        if (complete) send({ t: 'answer', id: ask.id, answers: picks })
    }}>
        {ask.title && <div>{ask.title}</div>}
        {ask.questions.map(q => <div class="question" key={q.id ?? q.question}>
            {q.header && <div class="question-header">{q.header}</div>}
            <div>{q.question}</div>
            <div class="options">{q.options.map(option => <button type="button" class={`option ${picks[q.id ?? q.question]?.includes(option.value ?? option.label) ? 'selected' : ''}`}
                aria-pressed={picks[q.id ?? q.question]?.includes(option.value ?? option.label) ?? false} onClick={() => toggle(q.id ?? q.question, option.value ?? option.label, q.multiSelect)}>
                <span>{option.label}</span>{option.description && <small>{option.description}</small>}
            </button>)}</div>
            {(!q.options.length || q.freeform) && <input aria-label={q.question} placeholder={q.options.length ? 'or type an answer' : ''}
                value={q.options.some(o => (o.value ?? o.label) === picks[q.id ?? q.question]?.[0]) ? '' : picks[q.id ?? q.question]?.[0] ?? ''}
                onInput={event => { const value = event.currentTarget.value; setPicks(old => ({ ...old, [q.id ?? q.question]: value ? [value] : [] })) }} />}
        </div>)}
        <div class="actions"><button type="button" onClick={() => send({ t: 'cancel' })}>cancel</button><button type="button" onClick={() => send({ t: 'answer', id: ask.id, answers: null })}>skip</button><button class="default-action" disabled={!complete}>submit</button></div>
    </form>
}

function Surface({ id, cwd, active, status }: { id: string; cwd: string; active: boolean; status: (state: State) => void }) {
    const [state, setState] = useState<State>({ id, cwd, rows: [], buttonState: 'send', ask: null, askq: null, unseen: false })
    const [input, setInput] = useState('')
    const scroller = useRef<HTMLDivElement>(null), field = useRef<HTMLInputElement>(null)
    const atBottom = useRef(true), first = useRef(true), visible = useRef(active)
    const transport = useRef<(command: Command) => void>(() => {})
    visible.current = active

    useEffect(() => {
        const url = new URL('/session', location.href)
        url.protocol = location.protocol === 'https:' ? 'wss:' : 'ws:'
        url.search = new URLSearchParams({ id, cwd }).toString()
        const socket = new WebSocket(url), pending: Command[] = []
        transport.current = command => socket.readyState === WebSocket.CONNECTING ? void pending.push(command) : socket.send(JSON.stringify(command))
        socket.onopen = () => { transport.current({ t: 'viewing', active: visible.current }); pending.splice(0).forEach(transport.current) }
        socket.onmessage = event => { const next: State = JSON.parse(event.data); setState(next); status(next) }
        socket.onclose = () => setState(old => ({ ...old, buttonState: 'send', rows: [...old.rows, { id: crypto.randomUUID(), kind: 'error', text: 'agent disconnected' }] }))
        return () => { socket.onclose = null; socket.close() }
    }, [id])

    useLayoutEffect(() => {
        transport.current({ t: 'viewing', active })
        if (active) field.current?.focus()
    }, [active])

    const lastText = state.rows.at(-1)?.text
    useLayoutEffect(() => {
        if (first.current || atBottom.current) scroller.current!.scrollTop = scroller.current!.scrollHeight
        if (state.rows.length) first.current = false
    }, [lastText])
    useEffect(() => { if (active) field.current?.focus() }, [])

    function sendOrStop(event: Event) {
        event.preventDefault()
        if (state.buttonState !== 'send') { transport.current({ t: 'stop' }); return }
        const text = input.trim()
        if (!text) return
        transport.current({ t: 'say', text })
        setState(old => ({ ...old, buttonState: 'pending', rows: [...old.rows, { id: crypto.randomUUID(), kind: 'user', text }] }))
        setInput('')
    }
    return <section class={`surface ${active ? 'active' : ''}`} aria-hidden={!active} inert={!active}>
        <div class="transcript" ref={scroller} onScroll={() => {
            const view = scroller.current!
            atBottom.current = view.scrollTop >= view.scrollHeight - view.clientHeight - 24
        }}><div class="rows">{state.rows.map(row => <RowView key={row.id} row={row} />)}</div></div>
        {state.ask && <div class="permission bar"><span>allow {state.ask.name}?</span><div class="actions">
            <button onClick={() => transport.current({ t: 'perm', id: state.ask!.id, allow: false })}>deny</button>
            <button class="default-action" onClick={() => transport.current({ t: 'perm', id: state.ask!.id, allow: true })}>allow</button>
        </div></div>}
        {state.askq && <Questions key={state.askq.id} ask={state.askq} send={command => transport.current(command)} />}
        <form class="composer" onSubmit={sendOrStop}>
            <input ref={field} placeholder="message" aria-label="message" value={input} onInput={event => setInput(event.currentTarget.value)} autoComplete="off" spellcheck={false} />
            <button>{state.buttonState}</button>
        </form>
    </section>
}

function App() {
    const [tabs, setTabs] = useState([initial]), [current, setCurrent] = useState(initial.id)
    const [active, setActive] = useState(!embedded && !document.hidden), [sidebar, setSidebar] = useState(false)
    const [past, setPast] = useState<PastChat[]>([]), [statuses, setStatuses] = useState<Record<string, State>>({})
    const size = useRef(settings.size), dismissed = useRef(false)
    const cwd = tabs.find(tab => tab.id === current)?.cwd ?? initial.cwd
    const pick = (chat: { id: string; cwd: string }) => {
        setTabs(old => old.some(tab => tab.id === chat.id) ? old : [...old, chat]); setCurrent(chat.id)
    }
    const status = (state: State) => {
        setStatuses(old => ({ ...old, [state.id]: state }))
        if (embedded) window.webkit?.messageHandlers.agent?.postMessage({ busy: state.buttonState !== 'send', unseen: state.unseen })
    }

    useEffect(() => {
        window.osmActive = setActive
        if (embedded) window.webkit?.messageHandlers.agent?.postMessage({ ready: true })
        const visibility = () => { if (!embedded) setActive(!document.hidden) }
        document.addEventListener('visibilitychange', visibility)
        return () => document.removeEventListener('visibilitychange', visibility)
    }, [])
    useEffect(() => {
        const url = new URL(location.href)
        url.searchParams.set('id', current); url.searchParams.set('cwd', cwd)
        history.replaceState(null, '', url)
    }, [current])
    useEffect(() => {
        if (!sidebar) return
        const timer = setTimeout(() => { void fetch(`/chats?${new URLSearchParams({ cwd })}`).then(r => r.json()).then(setPast) }, settings.sidebar.slidedelay * 1000)
        return () => clearTimeout(timer)
    }, [sidebar, current])
    useEffect(() => {
        if (embedded) return
        const down = (event: KeyboardEvent) => {
            if (!event.altKey || event.repeat) return
            if (event.key === 'Alt') { if (!dismissed.current) setSidebar(true); return }
            if (!['BracketLeft', 'BracketRight'].includes(event.code)) { dismissed.current = true; setSidebar(false) }
            if (['KeyT', 'KeyW', 'BracketLeft', 'BracketRight', 'Equal', 'Minus'].includes(event.code)) event.preventDefault()
            if (event.code === 'KeyT') pick({ id: crypto.randomUUID(), cwd })
            if (event.code === 'KeyW') {
                void fetch(`/session?${new URLSearchParams({ id: current, cwd })}`, { method: 'DELETE' })
                const remaining = tabs.filter(tab => tab.id !== current)
                setTabs(remaining); setCurrent(remaining.at(-1)?.id ?? '')
            }
            if (tabs.length && ['BracketLeft', 'BracketRight'].includes(event.code)) {
                const offset = event.code === 'BracketLeft' ? -1 : 1
                setCurrent(tabs[(tabs.findIndex(tab => tab.id === current) + offset + tabs.length) % tabs.length].id)
            }
            if (['Equal', 'Minus'].includes(event.code)) {
                size.current = Math.min(48, Math.max(6, size.current + (event.code === 'Equal' ? 1 : -1)))
                setFont(size.current)
                void fetch('/font', { method: 'POST', body: JSON.stringify({ size: size.current }) })
            }
        }
        const up = (event: KeyboardEvent) => { if (!event.altKey) { dismissed.current = false; setSidebar(false) } }
        const blur = () => { dismissed.current = false; setSidebar(false) }
        window.addEventListener('keydown', down); window.addEventListener('keyup', up); window.addEventListener('blur', blur)
        return () => { window.removeEventListener('keydown', down); window.removeEventListener('keyup', up); window.removeEventListener('blur', blur) }
    }, [tabs, current])

    const tilde = (path: string) => path.startsWith(settings.home) ? `~${path.slice(settings.home.length)}` : path
    return <main class="viewer">
        {tabs.map(tab => <Surface key={tab.id} {...tab} active={active && current === tab.id} status={status} />)}
        {!embedded && <aside class={sidebar ? 'visible' : ''}>
            {tabs.map(tab => <button class={`sidebar-row ${tab.id === current ? 'selected' : ''}`} onClick={() => setCurrent(tab.id)}>
                <span>{tilde(tab.cwd)}</span>{statuses[tab.id]?.buttonState !== 'send' && statuses[tab.id] ? <i class="busy" /> : statuses[tab.id]?.unseen && <i />}
            </button>)}
            {!!past.length && <><h2>PAST CHATS</h2>{past.map(chat => <button class="sidebar-row" onClick={() => pick(chat)}>{chat.title}</button>)}</>}
        </aside>}
    </main>
}
render(<App />, document.getElementById('app')!)
