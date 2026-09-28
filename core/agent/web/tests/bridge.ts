// a real child process replaying the provider protocol, without model calls or credentials.
import type { msgIn, msgOut } from "../../proto"
const emit = (event: msgOut) => process.send!(event)
const end = () => emit({ t: 'end', error: false })
const delta = (response: string) => emit({ t: 'delta', response })

process.on('message', async (message: msgIn) => {
    if (message.t === 'stop') { delta('stopped'); end(); return }
    if (message.t === 'perm') { delta(message.allow ? 'allowed' : 'denied'); end(); return }
    if (message.t === 'answer') { delta(JSON.stringify(message.answers)); end(); return }
    if (message.t !== 'say') return
    switch (message.text) {
        case 'show me how the agent works':
            delta('the agent streams **responses** and `tool calls`.\nhere is a [link](https://example.com).\n\n# heading\n- first item\n- second item')
            emit({ t: 'tool', name: 'Read', input: { path: '/Users/brad/git/osmium/core/agent/index.ts' } })
            delta('ready to continue.')
            emit({ t: 'end', error: true })
            emit({ t: 'ask', id: 'permission', name: 'Read', input: {} })
            emit({ t: 'askq', id: 'question', questions: [{ question: 'which approach?', header: 'approach', options: [{ label: 'small', description: 'keep the change focused' }, { label: 'broad', description: 'update every caller' }] }] })
            end(); return
        case 'permissions': emit({ t: 'ask', id: 'permission', name: 'Read', input: {} }); return
        case 'questions': emit({ t: 'askq', id: 'question', questions: [
            { question: 'which approach?', header: 'approach', options: [{ label: 'small', description: 'focused' }, { label: 'broad' }] },
            { question: 'which checks?', multiSelect: true, options: [{ label: 'unit' }, { label: 'browser' }] },
        ] }); return
        case 'form': emit({ t: 'askq', id: 'form', title: 'details', questions: [
            { id: 'name', question: 'your name', required: true, options: [] },
            { id: 'mode', question: 'mode', required: false, options: [{ label: 'simple', value: 'simple_value' }] },
        ] }); return
        case 'dismiss':
            emit({ t: 'ask', id: 'dismissed', name: 'Read', input: {} })
            await Bun.sleep(200)
            emit({ t: 'dismiss', id: 'dismissed' }); end(); return
        case 'wait': delta('working'); return
        case 'exit': process.exit(7)
        case 'stderr exit': {
            const adapter = Bun.spawn([process.execPath, '-e', 'console.error("provider authentication failed: sign in again"); process.exit(1)'], { stderr: 'inherit' })
            await adapter.exited
            throw new Error('adapter exited')
        }
        case 'resume': delta(`${process.argv[3]}|${process.argv[4]}`); end(); return
        case 'cwd': delta(process.cwd()); end(); return
        case 'unsafe': delta('<img src=x onerror=alert(1)> [click](javascript:alert(1)) **safe**'); end(); return
        case 'long':
            for (let i = 0; i < 70; i++) { delta(`line ${i}\n`); emit({ t: 'tool', name: 'Read', input: { path: `/tmp/${i}.txt` } }) }
            return
        case 'finish later':
            delta('waiting')
            await Bun.sleep(400)
            delta(' done'); end(); return
        default:
            emit({ t: 'delta', think: 'thinking ', response: 'ignored' })
            await Bun.sleep(40)
            delta('hello **world**')
            emit({ t: 'tool', name: 'Read', input: { path: '/tmp/example.ts' } })
            delta('finished'); end()
    }
})
await Bun.sleep(100)
emit({ t: 'session', id: process.argv[3] || 'backend-session', spec: process.argv[4] || 'fixture/model' })
emit({ t: 'ready' })
