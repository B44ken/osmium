#!/usr/bin/env bun

const tabs = [{ type: 'term', path: import.meta.dir, name: import.meta.dir }]
let active = tabs[0]

const start = async () => {
  await Bun.$`swift build`.catch(process.exit)
  const app = Bun.spawn(['.build/debug/App'], { stdin: 'pipe' })
  // app.stdin.write(`{ "cmd": "new_edit", "path": "${active.path}/hello.txt" }\n`)
  app.stdin.write(`{ "cmd": "set_text", "msg": "helo wrld" }\n`)
  app.stdin.write(`{ "cmd": "new_term", "path": "${active.path}" }\n`)
  app.exited.then(code => code == 0 ? true : console.error(`bun exit(${code})`))
}

await start()
