#!/usr/bin/env bun
import { spawn, spawnSync } from 'node:child_process'
import { access, mkdir, writeFile, symlink, rm } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { ensureOsmDir, sendCommand, waitForSocket } from './ipc.ts'
import { readConfig, writeConfigFlat } from './config.ts'
import type { Command } from './protocol.ts'

const OSM = fileURLToPath(new URL('..', import.meta.url))

const cwd = process.cwd()

function parseCommand(args: string[]): Command {
  const [one, two, ...more] = args // subcommand, target (url/folder/wtv), more is unused rn
  if (!one) return { type: 'open-terminal', cwd }
  else if (one === 'edit') {
    if (!two) throw new Error('usage: osm edit <file>')
    return { type: 'open-editor', path: resolve(cwd, two), cwd }
  } else if (one === 'web') {
    if (!two) throw new Error('usage: osm web <url>')
    return { type: 'open-browser', url: 'https://' + two.split('://').pop(), cwd }
  } else if (one === 'bind') {
    if (!two || !more[0]) throw new Error('usage: osm bind <event> <command>')
    return { type: 'add-bind', event: two, command: more[0], cwd }
  } else throw new Error(`unknown subcommand: ${one}`)
}

const findExecutable = async (which='debug') => join(OSM + '/native/.build/' + which + '/Osmium')

async function ensureBuild() {
  if (await findExecutable()) return
  const r = spawnSync('swift', ['build', '-c', 'release', '--package-path', join(OSM, 'native')], { cwd: OSM, stdio: 'inherit' })
  if (r.status !== 0) throw new Error('native build failed')
}

async function launch() {
  const exe = await findExecutable()
  if (!exe) throw new Error('executable not found after build')

  const macOS = join(OSM, '.native-run', 'Osmium.app', 'Contents', 'MacOS')
  const bundled = join(macOS, 'OsmiumApp')
  
  await mkdir(macOS, { recursive: true })
  
  try { await rm(bundled, { force: true }) } catch {}
  await symlink(exe, bundled)
  
  await writeFile(join(OSM, '.native-run/Osmium.app/Contents/Info.plist'), await Bun.file(join(OSM, 'src/plist.xml')).text())

  const child = spawn(bundled, [], { cwd: OSM, detached: true, stdio: 'ignore' })
  child.unref()
}


async function main() {
  const cmd = parseCommand(process.argv.slice(2))
  await ensureOsmDir()
  await writeConfigFlat(await readConfig())
  if (await sendCommand(cmd)) return
  await ensureBuild()
  await launch()
  await waitForSocket()
  await sendCommand(cmd)
}

main().catch(e => {
  process.stderr.write(e?.message ?? e ?? 'unknown error')
  process.exitCode = 1
})
