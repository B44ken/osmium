#!/usr/bin/env bun
import readline from 'node:readline'
import { reduceSidebar, type SidebarAction, type SidebarContext, type SidebarResponse, type SidebarState } from '../sidebar/engine.ts'
import { reduceAgent, type AgentReducerAction, type AgentReducerState } from '../agent/reducer.ts'

type AppBridgeRequest =
  | {
      id: number
      method: 'sidebar/reduce'
      params: {
        state: SidebarState | null
        context: SidebarContext
        action: SidebarAction
      }
    }
  | {
      id: number
      method: 'agent/reduce'
      params: {
        state: AgentReducerState | null
        cwd: string
        action: AgentReducerAction
      }
    }

type AppBridgeResponse =
  | { id: number; result: { sidebar: SidebarResponse } }
  | { id: number; result: { agent: AgentReducerState } }
  | { id: number; error: { message: string } }

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
})

for await (const line of rl) {
  const trimmed = line.trim()
  if (!trimmed)
    continue

  let response: AppBridgeResponse
  try {
    const request = JSON.parse(trimmed) as AppBridgeRequest
    switch (request.method) {
      case 'sidebar/reduce':
        response = {
          id: request.id,
          result: {
            sidebar: reduceSidebar(request.params.state, request.params.context, request.params.action),
          },
        }
        break
      case 'agent/reduce':
        response = {
          id: request.id,
          result: {
            agent: reduceAgent(request.params.state, request.params.cwd, request.params.action),
          },
        }
        break
    }
  } catch (error) {
    response = {
      id: -1,
      error: { message: error instanceof Error ? error.message : String(error) },
    }
  }

  process.stdout.write(`${JSON.stringify(response)}\n`)
}
