import { basicSetup } from "codemirror"
import { EditorState, Compartment } from "@codemirror/state"
import { EditorView, keymap, crosshairCursor } from "@codemirror/view"
import { indentWithTab } from "@codemirror/commands"
import { LanguageDescription } from "@codemirror/language"
import { languages } from "@codemirror/language-data"
import { oneDark } from "@codemirror/theme-one-dark"
import { languageServer } from "codemirror-languageserver"

// injected per request by server.ts — only the font, so keys never reach the browser
declare global {
    interface Window {
        FONT: { mono: string; sans: string; size: number }
        osmFont: (size: number) => void
    }
}

const fontComp = new Compartment()
const fontTheme = (size: number) =>
    EditorView.theme({ '&': { fontSize: `${size}px` }, '.cm-scroller': { fontFamily: window.FONT.mono } })

const path = new URLSearchParams(location.search).get("path") ?? "/tmp/untitled.ts"
const ext = path.slice(path.lastIndexOf(".") + 1)
const dir = path.slice(0, path.lastIndexOf("/"))

// lsp language ids, not file extensions: this is what `textDocument/didOpen` must carry, and it is
// also what server.ts keys its language servers on — so the mapping lives here only
const ids: Record<string, string> = {
    ts: 'typescript', mts: 'typescript', cts: 'typescript', tsx: 'typescriptreact',
    js: 'javascript', mjs: 'javascript', cjs: 'javascript', jsx: 'javascriptreact',
    py: 'python', pyi: 'python',
    c: 'c', h: 'c',
    cc: 'cpp', cpp: 'cpp', cxx: 'cpp', hh: 'cpp', hpp: 'cpp', hxx: 'cpp',
    yaml: 'yaml', yml: 'yaml',
}
const id = ids[ext]

const language = LanguageDescription.matchFilename(languages, path.slice(path.lastIndexOf('/') + 1))
    // preserve existing aliases absent from the registry, such as .pyi
    ?? (id ? LanguageDescription.matchLanguageName(languages, id, false) : null)
const lang = await language?.load()

// an extension with no server gets no socket at all — opening one only to be closed 1008 leaves a
// half-wired client that then writes didOpen into a dead socket
const ls = id ? languageServer({
    serverUri: `ws://${location.host}/lsp?lang=${id}`, rootUri: `file://${dir}`, documentUri: `file://${path}`, languageId: id, workspaceFolders: [{ name: dir, uri: `file://${dir}` }]
}) : []

const save = (view: EditorView) =>
    Boolean(fetch(`/file?path=${encodeURIComponent(path)}`, { method: "POST", body: view.state.doc.toString() }))

const text = await (await fetch(`/file?path=${encodeURIComponent(path)}`)).text()

const view = new EditorView({
    parent: document.body, state: EditorState.create({
        doc: text, extensions: [
            basicSetup, oneDark, EditorView.lineWrapping, crosshairCursor(),
            fontComp.of(fontTheme(window.FONT.size)),
            keymap.of([{ key: "Mod-s", run: save }, {}, indentWithTab]),
        ].concat(lang ? [lang] : [], ls)
    })
})
view.focus()

// called by the app on opt+/opt-
window.osmFont = size => view.dispatch({ effects: fontComp.reconfigure(fontTheme(size)) })
