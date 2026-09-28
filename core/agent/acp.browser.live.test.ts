import { expect, test } from 'bun:test'
import { chromium, expect as ui } from '@playwright/test'
import { mkdtemp, rm } from 'node:fs/promises'
import { join } from 'node:path'
import { serveAgent } from './web/server'

test.skipIf(!process.env.OSMIUM_LIVE_TESTS)('gpt async questions work during and after a turn in the browser', async () => {
    const cwd = await mkdtemp('/tmp/osmium-acp-browser-')
    const launcher = join(cwd, 'bridge.ts')
    await Bun.write(launcher, `import config from ${JSON.stringify(join(import.meta.dir, '../config.ts'))}
config.agent.model = 'codex/gpt-6-sol'
config.agent.effort = 'low'
config.agent.permissions = 'auto'
await import(${JSON.stringify(join(import.meta.dir, 'index.ts'))})
`)
    const app = serveAgent({ port: 0, home: cwd, bridge: launcher })
    const browser = await chromium.launch()
    try {
        const page = await browser.newPage()
        await page.goto(`${app.server.url}?${new URLSearchParams({ id: crypto.randomUUID(), cwd })}`)
        const send = async (text: string) => {
            await page.getByRole('textbox', { name: 'message', exact: true }).fill(text)
            await page.getByRole('textbox', { name: 'message', exact: true }).press('Enter')
        }
        await send('Integration test: use request_user_input_async to ask me to choose violet or amber. While my answer is pending, run a shell command printing WORK_WHILE_WAITING. Then wait for my answer and report my chosen color. Do not read files or use any other tools.')
        await ui(page.locator('.questions')).toBeVisible({ timeout: 60_000 })
        await ui(page.locator('.tool').filter({ hasText: 'WORK_WHILE_WAITING' })).toBeVisible({ timeout: 60_000 })
        await ui(page.locator('.questions')).toBeVisible()
        await page.getByRole('button', { name: 'violet', exact: true }).click()
        await page.locator('.questions input').fill('teal')
        await ui(page.getByRole('button', { name: 'violet', exact: true })).toHaveAttribute('aria-pressed', 'false')
        await page.getByRole('button', { name: 'submit', exact: true }).click()
        await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible({ timeout: 60_000 })
        await ui(page.locator('.assistant').last()).toContainText('teal')
        await ui(page.locator('.questions')).toHaveCount(0)
        await ui(page.locator('.user').last()).toContainText('teal')

        await send('Now use request_user_input_async to ask which snack I want, with choices apple and cookie. Immediately end your turn after asking; do not wait for an answer. I will answer after your turn has finished.')
        await ui(page.locator('.questions')).toBeVisible({ timeout: 60_000 })
        await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible({ timeout: 60_000 })
        await page.reload()
        await ui(page.locator('.questions')).toBeVisible()
        await page.getByRole('button', { name: 'cookie', exact: true }).click()
        await page.getByRole('button', { name: 'submit', exact: true }).click()
        await ui(page.locator('.user').last()).toContainText('cookie')
        await ui(page.getByRole('button', { name: 'send', exact: true })).toBeVisible({ timeout: 60_000 })
        await ui(page.locator('.assistant').last()).toContainText('cookie')
        await ui(page.locator('.questions')).toHaveCount(0)
        expect(await page.locator('.error').count()).toBe(0)
        await page.screenshot({ path: '/tmp/osmium-acp-browser.png' })
    } finally {
        await browser.close()
        await app.stop()
        await rm(cwd, { recursive: true })
    }
}, 240_000)
