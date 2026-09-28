import { expect, test } from 'bun:test'
import { EventEmitter, once } from 'node:events'
import { mkdtemp, rm } from 'node:fs/promises'
import { join } from 'node:path'
import type { msgIn, msgOut } from './proto'

// uses the real adapter and existing codex login. opt in to subscription usage.
test.skipIf(!process.env.OSMIUM_LIVE_TESTS)('codex bridge: tools, resume, cancellation, and another turn', async () => {
    const cwd = await mkdtemp('/tmp/osmium-acp-test-')
    const launcher = join(cwd, 'bridge.ts')
    await Bun.write(launcher, `import config from ${JSON.stringify(join(import.meta.dir, '../config.ts'))}
config.agent.effort = 'low'
config.agent.permissions = 'ask'
await import(${JSON.stringify(join(import.meta.dir, 'index.ts'))})
`)
    const boot = (resume = '') => {
        const events: msgOut[] = [], changed = new EventEmitter()
        const proc = Bun.spawn([process.execPath, launcher, cwd, resume, 'codex/gpt-6-luna'], {
            cwd, stdin: 'ignore', stdout: 'ignore', stderr: Bun.file(join(cwd, `bridge-${resume || 'new'}.log`)),
            ipc: (event: msgOut) => { events.push(event); changed.emit('message') },
        })
        return { events, proc,
            send: (message: msgIn) => proc.send(message),
            wait: async <T extends msgOut['t']>(t: T, after = 0): Promise<Extract<msgOut, { t: T }>> => {
                for (;;) {
                    const found = events.slice(after).find(e => e.t === t)
                    if (found) return found as Extract<msgOut, { t: T }>
                    await Promise.race([once(changed, 'message'), proc.exited.then(code => {
                        throw new Error(`bridge exited ${code}; see ${cwd}`)
                    })])
                }
            },
            close: async () => { proc.kill(); expect(await proc.exited).toBe(0) },
        }
    }
    let bridge = boot()
    try {
        await bridge.wait('ready')
        const session = await bridge.wait('session')
        const token = crypto.randomUUID()
        await Bun.write(join(cwd, 'input.txt'), token)
        let after = bridge.events.length
        bridge.send({ t: 'say', text: 'Read input.txt using a tool and write its exact contents to output.txt. Remember its contents as the test token. Reply with the token.' })
        expect(await bridge.wait('end', after)).toMatchObject({ error: false })
        expect(await Bun.file(join(cwd, 'output.txt')).text()).toBe(token)
        expect(bridge.events.slice(after).some(e => e.t === 'tool')).toBe(true)
        expect(bridge.events.slice(after).filter(e => e.t === 'delta').map(e => e.response ?? '').join('')).toContain(token)

        await bridge.close()
        bridge = boot(session.id)
        await bridge.wait('ready')
        expect(await bridge.wait('session')).toMatchObject({ id: session.id })
        expect(bridge.events.some(e => e.t === 'delta' || e.t === 'tool')).toBe(false)
        after = bridge.events.length
        bridge.send({ t: 'say', text: 'What was the test token? Reply from conversation memory; do not use tools.' })
        expect(await bridge.wait('end', after)).toMatchObject({ error: false })
        expect(bridge.events.slice(after).filter(e => e.t === 'delta').map(e => e.response ?? '').join('')).toContain(token)

        after = bridge.events.length
        bridge.send({ t: 'say', text: 'Run sleep 30 in the shell, then reply done.' })
        await bridge.wait('tool', after)
        bridge.send({ t: 'stop' })
        expect(await bridge.wait('end', after)).toMatchObject({ error: false, message: 'cancelled' })
        after = bridge.events.length
        bridge.send({ t: 'say', text: 'Reply with exactly: still running. Do not run tools.' })
        expect(await bridge.wait('end', after)).toMatchObject({ error: false })
        expect(bridge.events.slice(after).filter(e => e.t === 'delta').map(e => e.response ?? '').join('')).toContain('still running')
    } finally {
        await bridge.close()
        await rm(cwd, { recursive: true })
    }
}, 180_000)
