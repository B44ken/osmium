#!/usr/bin/env bun
import { spawn, spawnSync } from 'node:child_process'
import { accessSync, constants, readdirSync, statSync } from 'node:fs'
import { mkdir, writeFile, symlink, rm } from 'node:fs/promises'
import { delimiter, dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { ensureOsmDir, sendCommand, waitForSocket } from './ipc.ts'
import type { Command } from './protocol.ts'

const OSM = fileURLToPath(new URL('..', import.meta.url))

const cwd = process.cwd()
const shellQuote = (value: string) => `'${value.replace(/'/g, `'\\''`)}'`

function newestNativeSourceMtime(dir: string): number {
  let newest = 0
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) {
      newest = Math.max(newest, newestNativeSourceMtime(path))
      continue
    }
    if (entry.name.endsWith('.swift') || entry.name === 'Package.swift')
      newest = Math.max(newest, statSync(path).mtimeMs)
  }
  return newest
}

function parseEditCommand(args: string[]): Command {
  const [file, ...rest] = args
  if (!file) throw new Error('usage: osm edit <file> [--hot <command>]')

  let hot: string | undefined
  for (let i = 0; i < rest.length; i++) {
    if (rest[i] !== '--hot') throw new Error(`unknown flag: ${rest[i]}`)
    hot = rest[i + 1]
    if (!hot) throw new Error('usage: osm edit <file> [--hot <command>]')
    i++
  }

  return { type: 'open-editor', path: resolve(cwd, file), cwd, hot }
}

export function parseCommand(args: string[]): Command {
  const [one, two] = args
  if (!one) return { type: 'open-terminal', cwd }
  else if (one === 'agent') {
    const target = two ? resolve(cwd, two) : cwd
    return { type: 'open-agent', cwd: target }
  }
  else if (one === 'edit' || one === 'editor') {
    return parseEditCommand(args.slice(1))
  } else if (one === 'web') {
    if (!two) throw new Error('usage: osm web <url>')
    return { type: 'open-browser', url: normalizeWebTarget(two), cwd }
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

const nativeExecutable = () => join(OSM, 'native', '.build', 'release', 'Osmium')

function ensureBuild() {
  try {
    const exe = nativeExecutable()
    accessSync(exe, constants.X_OK)
    if (statSync(exe).mtimeMs >= newestNativeSourceMtime(join(OSM, 'native')))
      return
  } catch {}

  const r = spawnSync('swift', ['build', '-c', 'release', '--package-path', join(OSM, 'native')], { cwd: OSM, stdio: 'inherit' })
  if (r.status !== 0) throw new Error('native build failed')
}

async function launch() {
  const exe = nativeExecutable()
  const path = [
    dirname(process.execPath),
    process.env.PATH,
  ].filter(Boolean).join(delimiter)

  const macOS = join(OSM, '.native-run', 'Osmium.app', 'Contents', 'MacOS')
  const bundled = join(macOS, 'OsmiumApp')
  const bundledNative = join(macOS, 'OsmiumBinary')
  
  await mkdir(macOS, { recursive: true })

  await rm(bundled, { force: true })
  await rm(bundledNative, { force: true })
  await symlink(exe, bundledNative)
  
  await writeFile(join(OSM, '.native-run/Osmium.app/Contents/Info.plist'), await Bun.file(join(OSM, 'src/plist.xml')).text())
  await writeFile(
    bundled,
    [
      '#!/bin/sh',
      `export PATH=${shellQuote(path)}`,
      `export BUN=${shellQuote(process.execPath)}`,
      'mkdir -p "$HOME/.osm"',
      `"${'$'}BUN" ${shellQuote(join(OSM, 'src', 'config-print.ts'))} > "$HOME/.osm/config" 2>/dev/null || true`,
      `exec ${shellQuote(bundledNative)} "${'$'}@"`,
      '',
    ].join('\n'),
    { mode: 0o755 }
  )

  const child = spawn(bundled, [], {
    cwd: OSM,
    detached: true,
    stdio: 'ignore',
    env: {
      ...process.env,
      PATH: path,
      BUN: process.execPath,
    },
  })
  child.unref()
}


export async function main() {
  const cmd = parseCommand(process.argv.slice(2))
  await ensureOsmDir()
  if (await sendCommand(cmd)) return
  ensureBuild()
  await launch()
  await waitForSocket()
  await sendCommand(cmd)
}

if (import.meta.main) {
  main().catch(e => {
    process.stderr.write(e?.message ?? e ?? 'unknown error')
    process.exitCode = 1
  })
}
