#!/usr/bin/env bun
import { spawn, spawnSync } from 'node:child_process'
import { accessSync, constants } from 'node:fs'
import { access, mkdir, writeFile, symlink, rm } from 'node:fs/promises'
import { delimiter, dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { ensureOsmDir, sendCommand, waitForSocket } from './ipc.ts'
import { readConfig, writeConfigFlat } from './config.ts'
import type { Command } from './protocol.ts'

const OSM = fileURLToPath(new URL('..', import.meta.url))

const cwd = process.cwd()

async function resolveCommand(name: string) {
  const dirs = (process.env.PATH ?? '').split(delimiter).filter(Boolean)
  const suffixes = process.platform === 'win32' ? ['', '.exe', '.cmd'] : ['']

  for (const dir of dirs)
    for (const suffix of suffixes) {
      const file = join(dir, name + suffix)
      try {
        await access(file, constants.X_OK)
        return file
      } catch {}
    }
}

function parseCommand(args: string[]): Command {
  const [one, two, ...more] = args // subcommand, target (url/folder/wtv), more is unused rn
  if (!one) return { type: 'open-terminal', cwd }
  else if (one === 'agent') {
    const target = two ? resolve(cwd, two) : cwd
    return { type: 'open-agent', cwd: target }
  }
  else if (one === 'edit') {
    if (!two) throw new Error('usage: osm edit <file>')
    return { type: 'open-editor', path: resolve(cwd, two), cwd }
  } else if (one === 'web') {
    if (!two) throw new Error('usage: osm web <url>')
    return { type: 'open-browser', url: normalizeWebTarget(two), cwd }
  } else if (one === 'bind') {
    if (!two || !more[0]) throw new Error('usage: osm bind <event> <command>')
    return { type: 'add-bind', event: two, command: more[0], cwd }
  } else throw new Error(`unknown subcommand: ${one}`)
}

function normalizeWebTarget(target: string): string {
  if (/^[a-zA-Z][a-zA-Z\d+.-]*:\/\//.test(target))
    return target

  const resolved = resolve(cwd, target)
  const looksLikePath = target.startsWith('/') || target.startsWith('./') || target.startsWith('../')
  try {
    accessSync(resolved)
    return pathToFileURL(resolved).href
  } catch {
    if (looksLikePath)
      return pathToFileURL(resolved).href
    return 'https://' + target
  }
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
  const codex = process.env.CODEX ?? await resolveCommand('codex')
  const node = process.env.NODE ?? await resolveCommand('node')
  const path = [
    dirname(process.execPath),
    codex && dirname(codex),
    node && dirname(node),
    process.env.PATH,
  ].filter(Boolean).join(delimiter)

  const macOS = join(OSM, '.native-run', 'Osmium.app', 'Contents', 'MacOS')
  const bundled = join(macOS, 'OsmiumApp')
  
  await mkdir(macOS, { recursive: true })
  
  try { await rm(bundled, { force: true }) } catch {}
  await symlink(exe, bundled)
  
  await writeFile(join(OSM, '.native-run/Osmium.app/Contents/Info.plist'), await Bun.file(join(OSM, 'src/plist.xml')).text())

  const child = spawn(bundled, [], {
    cwd: OSM,
    detached: true,
    stdio: 'ignore',
    env: {
      ...process.env,
      PATH: path,
      BUN: process.execPath,
      ...(codex ? { CODEX: codex } : {}),
      ...(node ? { NODE: node } : {}),
    },
  })
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
