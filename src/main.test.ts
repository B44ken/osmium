import { expect, test } from 'bun:test'
import { parseCommand } from './main.ts'

test('parseCommand keeps edit hot command', () => {
  expect(parseCommand(['edit', 'balance.py', '--hot', 'py balance.py'])).toEqual({
    type: 'open-editor',
    path: `${process.cwd()}/balance.py`,
    cwd: process.cwd(),
    hot: 'py balance.py',
  })
})

test('parseCommand rejects edit flags without values', () => {
  expect(() => parseCommand(['edit', 'balance.py', '--hot'])).toThrow('usage: osm edit <file> [--hot <command>]')
})
