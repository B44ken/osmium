import { basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { EditorView, keymap, crosshairCursor } from "@codemirror/view"
import { indentWithTab } from "@codemirror/commands"
import { javascript } from "@codemirror/lang-javascript"
import { python } from "@codemirror/lang-python"
import { oneDark } from "@codemirror/theme-one-dark"
import { languageServer } from "codemirror-languageserver"
import config from '../../osm.yaml'

const path = new URLSearchParams(location.search).get("path") ?? "/tmp/untitled.ts"
const ext = path.slice(path.lastIndexOf(".") + 1)
const dir = path.slice(0, path.lastIndexOf("/"))

let lang
if (['js', 'jsx', 'ts', 'tsx'].includes(ext)) lang = javascript({ typescript: true, jsx: ext === "tsx" })
if (ext === "py") lang = python()

const ls = languageServer({
    serverUri: `ws://${location.host}/lsp?lang=${ext}`, rootUri: `file://${dir}`, documentUri: `file://${path}`, languageId: ext, workspaceFolders: [{ name: dir, uri: `file://${dir}` }]
})

const save = (view: EditorView) =>
    Boolean(fetch(`/file?path=${encodeURIComponent(path)}`, { method: "POST", body: view.state.doc.toString() }))

const text = await (await fetch(`/file?path=${encodeURIComponent(path)}`)).text()

const view = new EditorView({
    parent: document.body, state: EditorState.create({
        doc: text, extensions: [
            basicSetup, oneDark, ls, EditorView.lineWrapping, crosshairCursor(),
            EditorView.theme({'&': { fontSize: `${config.font.size}px` }, '.cm-scroller': { fontFamily: config.font.mono } }),
            keymap.of([{ key: "Mod-s", run: save }, {}, indentWithTab]),
        ].concat(lang ? [lang] : [])
    })
})
view.focus()