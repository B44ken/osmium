import { YAML } from 'bun'
import os from 'node:os'
import path from 'node:path'

const std = {
    options: {
        start_dir: os.homedir(),
        font_size: 15,
        font_mono: 'SF Mono',
        font_sans: 'Helvetica Neue',
        tabs_slide_ms: 150,
        tabs_slide_delay: 100,
        terminal: {
            font_size: 15,
        },
        editor: {
            font_size: 15,
        },
    },
    window: {
        min_width: 1180,
        min_height: 760,
        max_width: 1680,
        max_height: 1120,
        tabs_width: 200,
    },
    agent: {
        thinking: 'xhigh',
    },
    theme: {
        shell_bg: '#00000000',
        panel_bg: '#0f1318ff',
        panel_border: '#ffffff1a',
        sidebar_stroke: '#ffffff29',
        sidebar_fill: '#ffffff09',
        overlay_text: '#f0f0f0f5',
        overlay_subdued: '#c2c2c2f0',
        terminal_bg: '#0f1318ff',
        terminal_foreground: '#e7ebf2ff',
        terminal_cursor: '#e7ebf2ff',
        editor_bg: '#101419ff',
        editor_text: '#e7ebf2ff',
        editor_cursor: '#e7ebf2ff',
        editor_invisibles: '#556170ff',
        editor_line_highlight: '#171d24ff',
        editor_selection: '#25415cff',
        editor_keywords: '#ff9b6aff',
        editor_commands: '#79d4c5ff',
        editor_types: '#70c7ffff',
        editor_attributes: '#ddb46eff',
        editor_variables: '#c7d5e8ff',
        editor_values: '#f0c674ff',
        editor_numbers: '#e3c26bff',
        editor_strings: '#a7d06fff',
        editor_characters: '#a7d06fff',
        editor_comments: '#728091ff'
    }
}

const record = (value: unknown): Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value) ? value as Record<string, unknown> : {}

const string = (value: unknown, fallback: string): string =>
    typeof value === 'string' && value.trim() ? value.trim() : fallback

export const readConfig = async () => {
    const file = Bun.file(path.join(os.homedir(), '.osm', 'osm.yaml'))
    if (!await file.exists()) return std
    const parsed = record(YAML.parse(await file.text()))
    const parsedOptions = record(parsed.options)
    return {
        ...std,
        options: {
            ...std.options,
            ...parsedOptions,
            start_dir: string(parsedOptions.start_dir ?? parsed.start_dir, std.options.start_dir),
        },
        window: { ...std.window, ...record(parsed.window) },
        agent: { ...std.agent, ...record(parsed.agent) },
        theme: { ...std.theme, ...record(parsed.theme) },
    }
}

export const flattenConfig = (obj: Record<string, unknown>, prefix = ''): string[] =>
    Object.entries(obj).flatMap(([k, v]) =>
        typeof v === 'object' && v !== null ? flattenConfig(v, `${prefix}${k}.`) : [`${prefix}${k}=${v}`])

export const serializeFlatConfig = (cfg: Record<string, unknown>) =>
    flattenConfig(cfg).join('\n') + '\n'
