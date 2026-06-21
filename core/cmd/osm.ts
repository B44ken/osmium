#!/usr/bin/env bun
import { $, file, sleep, spawn, FileSink } from "bun"
import { resolve } from "path"

const base = `${import.meta.dir}/../../`
const help = `osmium\n  osm term\n  osm edit PATH\n  osm web URL\n  osm agent`

const types = ["term", "edit", "web", "agent"]
const [sub, arg] = process.argv.slice(2)

if((!types.includes(sub))) console.log(help), process.exit(0)

const type = sub ?? "term"

const establish = async (): Promise<boolean> => {
  if (!file(`/tmp/osm.fifo`).exists())
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

const ensureEditServer = async () => {
  const up = async () => fetch("http://127.0.0.1:7223/", { signal: AbortSignal.timeout(300) }).then(() => true, () => false)
  if (await up()) return
  spawn([process.execPath, `${base}core/web/server.ts`], { stdout: "inherit", stderr: "inherit" })
  for (let i = 0; i < 50; i++) { if (await up()) return; await sleep(100) }
}

const send = (fs: FileSink, type: string, path: string) =>
  fs.write(`{ "cmd": "new", "type": "${type}", "path": "${path}", "id": "${crypto.randomUUID()}" }\n`)

const inject = async (type: string, path: string) => {
  const fs = file(`/tmp/osm.fifo`).writer()
  send(fs, type, path)
  await fs.end()
}

const fresh = await establish()
if (type === 'edit')
  await ensureEditServer().then(() => inject('edit', resolve(arg ?? '.')))
else if (!(fresh && type == 'term'))
  await inject(type, process.cwd())

process.exit(0)
