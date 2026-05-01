#!/usr/bin/env bun
import { $, file, sleep, spawn, FileSink } from "bun"

const base = `${import.meta.dir}/../`

const establish = async (): Promise<FileSink> => {
  // make fifo if needed
  if (!file(`/tmp/osm.fifo`).exists())
    await $`mkfifo /tmp/osm.fifo`

  // build if needed
  await $`swift build --package-path ${base}mac`.quiet().catch(p => {
    console.log(p.stdout.toString())
    process.exit(1)
  })

  // run if needed
  try { await $`pgrep Osmium`.quiet() }
  catch { spawn([`${base}mac/.build/debug/Osmium`], { stdout: 'inherit' }) }

  await sleep(1000)
  return file(`/tmp/osm.fifo`).writer()
}

const newTerm = (fs: FileSink, path: string) =>
  fs.write(`{ "cmd": "new", "type": "term", "path": "${path}", "id": "${crypto.randomUUID()}" }\n`)

const fs = await establish()
newTerm(fs, "/dev/one")
await sleep(500)
newTerm(fs, "/dev/two")