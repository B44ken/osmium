#!/usr/bin/env bun
import { spawn, ChildProcess } from "node:child_process"
import { StreamMessageReader, StreamMessageWriter } from "vscode-jsonrpc/node"
import { load } from '../config'

const bin = `${import.meta.dir}/../../node_modules/.bin`
// keyed by lsp language id, which is what client.ts sends and what it puts in textDocument/didOpen
const tsls = `${bin}/typescript-language-server`
const servers: Record<string, string[]> = {
  typescript: [tsls, '--stdio'], typescriptreact: [tsls, '--stdio'],
  javascript: [tsls, '--stdio'], javascriptreact: [tsls, '--stdio'],
  python: [`${bin}/pyright-langserver`, '--stdio'],
  c: ['clangd'], cpp: ['clangd'],
  yaml: [`${bin}/yaml-language-server`, '--stdio'],
}

// client.ts is not in this module's import graph, so the `bun --hot` watcher that picks up edits to
// this file can't see it — rebuild per request instead (~20ms) so a tab never opens a stale bundle
const clientJS = async () =>
  (await Bun.build({ entrypoints: [`${import.meta.dir}/client.ts`], target: "browser" })).outputs[0].text()

// read per request so a newly opened editor tab picks up the current opt+/opt- size, and send
// only the font — a static yaml import would inline the api keys into the served bundle
const html = () => {
  const { mono, sans, size, sizes } = load().font
  const font = JSON.stringify({ mono, sans, size: sizes.edit ?? size })
  return `<!doctype html><meta charset=utf8>
<style>html,body{margin:0;height:100%;background:#282c34}.cm-editor{height:100vh}.cm-scroller{font-family:ui-monospace,Menlo,monospace}</style>
<body><script>window.FONT=${font}</script><script type=module src=/client.js></script>`
}

type Sock = Bun.ServerWebSocket<{ lang: string; proc?: ChildProcess; writer?: StreamMessageWriter }>

Bun.serve<{ lang: string }>({
  port: 7223,
  async fetch(req, server) {
    const { pathname, searchParams } = new URL(req.url)
    if (pathname === "/lsp") {
      const up = server.upgrade(req, { data: { lang: searchParams.get("lang")! } })
      return new Response(null, { status: up ? 101 : 400 })
    }
    if (pathname === "/client.js")
      return new Response(await clientJS(), { headers: { "content-type": "text/javascript", "cache-control": "no-store" } })
    if (pathname === "/file") {
      const path = searchParams.get("path")!
      if (req.method === "POST") { await Bun.write(path, await req.text()); return new Response("ok") }
      // a path that doesn't exist yet opens as an empty buffer and the POST above creates it on save;
      // streaming a missing Bun.file instead makes bun swap in its 66kb error page as the document
      const f = Bun.file(path)
      return new Response(await f.exists() ? f : "")
    }
    return new Response(html(), { headers: { "content-type": "text/html" } })
  },
  websocket: {
    open(ws: Sock) {
      if (!servers[ws.data.lang]) return ws.close(1008, `no lsp for ${ws.data.lang}`)
      const [cmd, ...args] = servers[ws.data.lang]
      const proc = spawn(cmd, args, { stdio: ["pipe", "pipe", "inherit"] })
      new StreamMessageReader(proc.stdout!).listen(msg => ws.send(JSON.stringify(msg)))
      ws.data.proc = proc
      ws.data.writer = new StreamMessageWriter(proc.stdin!)
    },
    message(ws: Sock, raw) { ws.data.writer!.write(JSON.parse(raw.toString())) },
    close(ws: Sock) { ws.data.proc?.kill() },
  },
})