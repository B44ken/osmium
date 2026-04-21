#!/usr/bin/env bun

const tabs = [
  { type: 'term', path: import.meta.dir, name: import.meta.dir }
]
let active = tabs[0]

const ensureApp = async () => {
  const files = await Bun.$`ls -t *.swift App`.text()
  if(!files.startsWith('./App\n')) {
    await Bun.$`swift build`.quiet()
      .catch(err => {
        console.log('swift build failed')
        exit(1)
      })
  }
}

const start = async () => {
  await ensureApp()
  const app = Bun.spawn(['.build/debug/App'], { stdin: 'pipe' })

  app.stdin.write(`{ "cmd": "new_term", "path": "${active.path}" }`)
  app.stdin.write(`{ "cmd": "new_edit", "path": "${active.path}/hello.txt" }`)

  app.exited.then(code => code || console.error(`bun exit(${code})`))
}

console.log(tabs)

await start()