#!/usr/bin/env bun
import { $, file, sleep, spawn, FileSink } from "bun"
import { resolve } from "path"
import { closeSync, openSync } from "node:fs"

const base = `${import.meta.dir}/../../`
const help = `osmium\n  osm term\n  osm edit PATH\n  osm web URL\n  osm agent`

const types = ["term", "edit", "web", "agent"]
const [sub, arg] = process.argv.slice(2)

if((!types.includes(sub))) console.log(help), process.exit(0)

const type = sub ?? "term"

const establish = async (): Promise<boolean> => {
  if (!await file(`/tmp/osm.fifo`).exists())
    await $`mkfifo /tmp/osm.fifo`

  try { await $`pgrep -a Osmium`.quiet(); return false }
  catch {
    await $`swift build --package-path ${base}mac`.quiet().catch(p => {
      console.log(p.stdout.toString())
      process.exit(1)
    })
    spawn([`${base}mac/.build/debug/Osmium`], { stdout: 'inherit' })
    await sleep(500)
    return true
  }
}

const ensureServer = async (port: number, script: string, hot = false) => {
  const up = async () => fetch(`http://127.0.0.1:${port}/`, { signal: AbortSignal.timeout(300) }).then(() => true, () => false)
  if (await up()) return
  // --hot: this server outlives the shell that spawned it, so without a watcher it would serve the
  // bundle it booted with forever. reloads in place, keeping open lsp sockets and the port.
  // servers outlive this terminal; inherited output becomes unusable when it closes.
  const log = openSync(`${base}log.txt`, 'a')
  spawn([process.execPath, ...(hot ? ['--hot'] : []), `${base}${script}`], { detached: true, stdin: 'ignore', stdout: log, stderr: log }).unref()
  closeSync(log)
  for (let i = 0; i < 50; i++) { if (await up()) return; await sleep(100) }
}

const send = (fs: FileSink, type: string, path: string) =>
  fs.write(JSON.stringify({ cmd: "new", type, path, id: crypto.randomUUID() }) + "\n")

const inject = async (type: string, path: string) => {
  const fs = file(`/tmp/osm.fifo`).writer()
  send(fs, type, path)
  await fs.end()
}

const fresh = await establish()
if (type === 'edit')
  await ensureServer(7223, 'core/web/server.ts', true).then(() => inject('edit', resolve(arg ?? '.')))
else if (type === 'agent')
  await ensureServer(7224, 'core/agent/web/server.ts').then(() => inject('agent', process.cwd()))
else if (type === 'web') {
  const url = arg === undefined ? 'about:blank'
    : await file(arg).exists() ? Bun.pathToFileURL(resolve(arg)).href
    : (URL.parse(arg) ?? new URL(`https://${arg}`)).href
  await inject('web', url)
}
else if (!(fresh && type == 'term'))
  await inject(type, process.cwd())

process.exit(0)
