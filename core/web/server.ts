#!/usr/bin/env bun
import { spawn, ChildProcess } from "node:child_process"
import { StreamMessageReader, StreamMessageWriter } from "vscode-jsonrpc/node"

const bin = `${import.meta.dir}/../../node_modules/.bin`
const servers: Record<string, string> = {
  typescript: `${bin}/typescript-language-server`,
  python: `${bin}/pyright-langserver`,
}

const built = await Bun.build({ entrypoints: [`${import.meta.dir}/client.ts`], target: "browser" })
if (!built.success) { console.error(built.logs); process.exit(1) }
const clientJS = await built.outputs[0].text()

const html = `<!doctype html><meta charset=utf8>
<style>html,body{margin:0;height:100%;background:#282c34}.cm-editor{height:100vh}.cm-scroller{font-family:ui-monospace,Menlo,monospace}</style>
<body><script type=module src=/client.js></script>`

type Sock = Bun.ServerWebSocket<{ lang: string; proc?: ChildProcess; writer?: StreamMessageWriter }>

Bun.serve<{ lang: string }>({
  port: 7223,
  async fetch(req, server) {
    const { pathname, searchParams } = new URL(req.url)
    if (pathname === "/lsp") {
      const up = server.upgrade(req, { data: { lang: searchParams.get("lang") ?? "typescript" } })
      return new Response(null, { status: up ? 101 : 400 })
    }
    if (pathname === "/client.js")
      return new Response(clientJS, { headers: { "content-type": "text/javascript", "cache-control": "no-store" } })
    if (pathname === "/file") {
      const path = searchParams.get("path")!
      if (req.method === "POST") { await Bun.write(path, await req.text()); return new Response("ok") }
      return new Response(Bun.file(path))
    }
    return new Response(html, { headers: { "content-type": "text/html" } })
  },
  websocket: {
    open(ws: Sock) {
      if (!servers[ws.data.lang]) return ws.close(1008, 'no lsp for this language')
      const proc = spawn(servers[ws.data.lang], ['--stdio'], { stdio: ["pipe", "pipe", "inherit"] })
      new StreamMessageReader(proc.stdout!).listen(msg => ws.send(JSON.stringify(msg)))
      ws.data.proc = proc
      ws.data.writer = new StreamMessageWriter(proc.stdin!)
    },
    message(ws: Sock, raw) { ws.data.writer!.write(JSON.parse(raw.toString())) },
    close(ws: Sock) { ws.data.proc?.kill() },
  },
})