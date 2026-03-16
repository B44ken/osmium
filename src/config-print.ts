#!/usr/bin/env bun
import { readConfig, serializeFlatConfig } from './config.ts'

process.stdout.write(serializeFlatConfig(await readConfig()))
