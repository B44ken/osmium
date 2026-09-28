import { afterAll, beforeAll, expect, test } from "bun:test"
import { chromium, expect as ui, type Browser } from "@playwright/test"
import { rm } from "node:fs/promises"
import { serveAgent } from "../server"

const home = `/tmp/osmium-agent-test-${crypto.randomUUID()}`
let app: ReturnType<typeof serveAgent>, browser: Browser
beforeAll(async () => {
    await Bun.write(`${home}/.osm/osm.yaml`, 'font:\n  sizes:\n    agent: 13\nagent:\n  keys:\n    preserved: secret-test-value\n')
    app = serveAgent({ port: 0, home, bridge: `${import.meta.dir}/bridge.ts` })
    browser = await chromium.launch()
})
afterAll(async () => { await browser.close(); await app.stop(); await rm(home, { recursive: true }) })

async function pageFor(id = crypto.randomUUID(), origin = app.server.url.toString()) {
    const page = await browser.newPage({ viewport: { width: 900, height: 600 } })
    await page.goto(`${origin}?${new URLSearchParams({ id, cwd: home })}`)
    await ui(page.getByRole('textbox', { name: 'message' })).toBeFocused()
    return { page, id }
}
const say = async (page: Awaited<ReturnType<typeof pageFor>>['page'], text: string) => {
    await page.getByRole('textbox', { name: 'message' }).fill(text)
    await page.getByRole('textbox', { name: 'message' }).press('Enter')
}

test('localhost settings and chat work; foreign hosts and origins are rejected', async () => {
    const localhost = `http://localhost:${app.server.port}/`
    for (const origin of [app.server.url.origin, new URL(localhost).origin]) {
        const settings = await fetch(`${origin}/settings`, { headers: { origin } })
        expect(settings.status).toBe(200)
        expect((await settings.json()).home).toBe(home)
        const forbidden = await fetch(`${origin}/settings`, { headers: { origin: 'https://other.example' } })
        expect(forbidden.status).toBe(403)
    }
    const foreignHost = await fetch(`${app.server.url}settings`, { headers: { host: `other.example:${app.server.port}` } })
    expect(foreignHost.status).toBe(403)
    const wrongPort = await fetch(`${app.server.url}settings`, { headers: { host: 'localhost:1' } })
    expect(wrongPort.status).toBe(403)
    const { page } = await pageFor(crypto.randomUUID(), localhost)
    await say(page, 'hello')
    await ui(page.locator('.assistant').last()).toHaveText('finished')
    await page.close()
})

test('streaming, pending input, transcript save and reconnect', async () => {
    const { page, id } = await pageFor()
    await say(page, 'hello')
    await ui(page.locator('.assistant').last()).toHaveText('finished')
    await ui(page.locator('.assistant').first()).toHaveText('thinking hello world')
    await ui(page.locator('.assistant strong')).toHaveText('world')
    await ui(page.locator('.tool')).toHaveText('[Read] /tmp/example.ts')
    await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible()
    await ui.poll(async () => (await app.chats.list(home)).length).toBeGreaterThan(0)
    const stored = await app.chats.file(id).json()
    expect(stored.session).toBe('backend-session')
    expect(stored.rows).toHaveLength(4)
    expect(stored.rows[0]).toEqual({ kind: 'user', text: 'hello' })
    const pid = (await app.sessions.get(id)!).process.pid
    await page.reload()
    await ui(page.locator('.assistant').last()).toHaveText('finished')
    expect((await app.sessions.get(id)!).process.pid).toBe(pid)
    await page.close()
}, 20_000)

test('allow and deny permissions', async () => {
    const { page } = await pageFor()
    await say(page, 'permissions')
    await page.getByRole('button', { name: 'deny', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('denied')
    await say(page, 'permissions')
    await page.getByRole('button', { name: 'allow', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('allowed')
    await ui(page.locator('.permission')).toHaveCount(0)
    await page.close()
})

test('single and multiple picks, completion and cancellation', async () => {
    const { page } = await pageFor()
    await say(page, 'questions')
    await ui(page.getByRole('button', { name: 'submit', exact: true })).toBeDisabled()
    await page.getByRole('button', { name: 'small focused', exact: true }).click()
    await page.getByRole('button', { name: 'broad', exact: true }).click()
    await ui(page.getByRole('button', { name: 'small focused', exact: true })).toHaveAttribute('aria-pressed', 'false')
    await page.getByRole('button', { name: 'unit', exact: true }).click()
    await page.getByRole('button', { name: 'browser', exact: true }).click()
    await page.getByRole('button', { name: 'submit', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('{"which approach?":["broad"],"which checks?":["unit","browser"]}')
    await say(page, 'questions')
    await page.getByRole('button', { name: 'cancel', exact: true }).click()
    await ui(page.locator('.questions')).toHaveCount(0)
    await ui(page.locator('.assistant').last()).toHaveText('stopped')
    await page.close()
})

test('busy send button interrupts and retains the draft', async () => {
    const { page } = await pageFor()
    await say(page, 'wait')
    await ui(page.getByRole('button', { name: 'thinking', exact: true })).toBeVisible()
    await page.getByRole('textbox').fill('next draft')
    await page.getByRole('button', { name: 'thinking', exact: true }).click()
    await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible()
    await ui(page.getByRole('textbox')).toHaveValue('next draft')
    await ui(page.locator('.user')).toHaveCount(1)
    await page.close()
})

test('structured form ids, free text, optional fields and decline', async () => {
    const { page } = await pageFor()
    await say(page, 'form')
    await ui(page.getByRole('button', { name: 'submit', exact: true })).toBeDisabled()
    await page.getByRole('textbox', { name: 'your name', exact: true }).fill('brad')
    await ui(page.getByRole('button', { name: 'submit', exact: true })).toBeEnabled()
    await page.getByRole('button', { name: 'simple', exact: true }).click()
    await page.getByRole('button', { name: 'submit', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('{"name":["brad"],"mode":["simple_value"]}')
    await say(page, 'form')
    await page.getByRole('button', { name: 'skip', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('null')
    await say(page, 'dismiss')
    await ui(page.locator('.permission')).toHaveCount(1)
    await ui(page.locator('.permission')).toHaveCount(0)
    await page.close()
})

test('scrollback stays put while output arrives; bottom follows output', async () => {
    const { page } = await pageFor()
    await say(page, 'long')
    await ui(page.locator('.tool')).toHaveCount(70)
    await ui.poll(() => page.locator('.transcript').evaluate(el => el.scrollHeight - el.scrollTop - el.clientHeight)).toBeLessThan(25)
    await page.locator('.transcript').evaluate(el => { el.scrollTop = 0; el.dispatchEvent(new Event('scroll')) })
    await page.getByRole('button', { name: 'thinking', exact: true }).click()
    await ui(page.locator('.assistant').last()).toHaveText('stopped')
    expect(await page.locator('.transcript').evaluate(el => el.scrollTop)).toBe(0)
    await page.close()
})

test('resume native and legacy transcripts, filtered and deduplicated history', async () => {
    const id = crypto.randomUUID()
    await Bun.write(app.chats.file(id), JSON.stringify({ id, title: 'native chat', cwd: home, updated: '2026-01-01T00:00:00Z', session: 'native-session', spec: 'fixture/native', rows: [{ kind: 'user', text: 'from native' }] }))
    await Bun.write(`${app.chats.legacyDir(home)}/${id}.jsonl`, JSON.stringify({ type: 'user', message: { content: 'duplicate' } }) + '\n')
    const legacy = crypto.randomUUID()
    await Bun.write(`${app.chats.legacyDir(home)}/${legacy}.jsonl`, [
        { type: 'user', message: { content: [{ type: 'text', text: 'old claude chat' }] } },
        { type: 'assistant', message: { content: [{ type: 'text', text: 'old answer' }, { type: 'tool_use', name: 'Read', input: { path: '/tmp/a' } }] } },
    ].map(value => JSON.stringify(value)).join('\n') + '\n{partial')
    const history = await app.chats.list(home)
    expect(history.filter(c => c.id === id)).toHaveLength(1)
    expect((await app.chats.list('/other-project'))).toHaveLength(0)
    const { page } = await pageFor(id)
    await ui(page.locator('.user')).toHaveText('from native')
    await say(page, 'resume')
    await ui(page.locator('.assistant').last()).toHaveText('native-session|fixture/native')
    await page.goto(`${app.server.url}?${new URLSearchParams({ id: legacy, cwd: home })}`)
    await ui(page.locator('.tool')).toHaveText('[Read] /tmp/a')
    await say(page, 'resume')
    await ui(page.locator('.assistant').last()).toHaveText(`${legacy}|claude/opus`)
    await page.close()
})

test('native visibility/status hooks, font hook, and safe inline markdown', async () => {
    const { page } = await pageFor()
    await page.evaluate(() => { window.osmActive(false); window.osmFont(19) })
    expect(await page.locator('.rows').evaluate(el => getComputedStyle(el).fontSize)).toBe('19px')
    await page.evaluate(() => window.osmActive(true))
    await say(page, 'unsafe')
    await ui(page.locator('.assistant strong')).toHaveText('safe')
    await ui(page.locator('[onerror], a[href^="javascript:"]')).toHaveCount(0)
    await say(page, 'wait')
    await ui(page.getByRole('button', { name: 'thinking', exact: true })).toBeVisible()
    await page.evaluate(() => window.osmActive(false))
    await page.locator('.composer button').evaluate((button: HTMLButtonElement) => button.click())
    await ui.poll(async () => (await [...app.sessions.values()].at(-1)!).state.unseen).toBe(true)
    await page.evaluate(() => window.osmActive(true))
    await ui.poll(async () => (await [...app.sessions.values()].at(-1)!).state.unseen).toBe(false)
    await page.close()
})

test('standalone sidebar, tabs, font persistence and key isolation', async () => {
    const { page } = await pageFor()
    await say(page, 'hello')
    await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible()
    await page.keyboard.down('Alt')
    await ui(page.locator('aside')).toHaveClass('visible')
    await ui(page.locator('aside h2')).toHaveText('PAST CHATS')
    await page.keyboard.up('Alt')
    await page.keyboard.press('Alt+KeyT')
    await ui(page.locator('.surface')).toHaveCount(2)
    await page.keyboard.press('Alt+BracketLeft')
    await ui(page.locator('.surface.active .assistant').last()).toHaveText('finished')
    await page.keyboard.press('Alt+Equal')
    await ui.poll(async () => (Bun.YAML.parse(await Bun.file(`${home}/.osm/osm.yaml`).text()) as any).font.sizes.agent).not.toBe(13)
    expect((Bun.YAML.parse(await Bun.file(`${home}/.osm/osm.yaml`).text()) as any).agent.keys.preserved).toBe('secret-test-value')
    expect(await page.content()).not.toContain('secret-test-value')
    await page.close()
})

test('subprocess errors stay visible and external origins cannot send commands', async () => {
    const { page } = await pageFor()
    await say(page, 'exit')
    await ui(page.locator('.error')).toHaveText('agent exited (code 7)')
    await say(page, 'hello')
    await ui(page.locator('.error').last()).toHaveText('agent not running')
    const forbidden = await fetch(`${app.server.url}font`, { method: 'POST', headers: { origin: 'https://other.example' }, body: '{"size":40}' })
    expect(forbidden.status).toBe(403)
    await page.close()
})

test('native reference layout', async () => {
    const { page } = await pageFor()
    await say(page, 'show me how the agent works')
    await ui(page.getByRole('button', { name: 'submit', exact: true })).toBeDisabled()
    await ui(page.locator('.assistant').first()).toContainText('# heading\n- first item')
    await page.screenshot({ path: '/tmp/osmium-agent-web-reference.png' })
    expect(await page.locator('.rows').evaluate(el => getComputedStyle(el).gap)).toBe('16px')
    expect(await page.locator('.composer').evaluate(el => Math.round(el.getBoundingClientRect().height))).toBe(40)
    await page.close()
})

test('adapter stderr and bridge stack traces reach the browser on exit', async () => {
    const { page } = await pageFor()
    await say(page, 'stderr exit')
    await ui(page.locator('.error')).toContainText('provider authentication failed: sign in again')
    await ui(page.locator('.error')).toContainText('error: adapter exited')
    await ui(page.locator('.error')).toContainText('bridge.ts:')
    await ui(page.locator('.error')).toContainText('agent exited (code 1)')
    await page.reload()
    await ui(page.locator('.error')).toContainText('provider authentication failed: sign in again')
    await page.close()
})

test('real bridge startup failures reach the browser before ready', async () => {
    const id = crypto.randomUUID()
    await Bun.write(app.chats.file(id), JSON.stringify({ id, title: 'bad provider', cwd: home, updated: '2026-09-28', session: '', spec: 'invalid/model', rows: [] }))
    const real = serveAgent({ port: 0, home })
    try {
        const { page } = await pageFor(id, real.server.url.toString())
        await ui(page.locator('.error')).toContainText('unsupported agent: invalid; use claude/model or codex/model')
        await ui(page.locator('.error')).toContainText('agent exited (code 1)')
        await page.close()
    } finally { await real.stop() }
})
