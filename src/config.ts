import { YAML } from 'bun'
import { writeFile } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

const std = {
    options: { font: 15, font_face: 'SF Mono', agent_font_face: 'Helvetica Neue' },
    binds: {
        show_tabs: 'opt',
        tab_up: 'opt [',
        tab_down: 'opt ]',
        new_surface: 'cmd t',
        close_tab: 'cmd w',
        save: 'cmd s', // todo: remove: should be handled by editor
        quit: 'cmd q',
        force_quit: 'ctrl q'
    },
    theme: {
        shell_bg: '#00000000',
        panel_bg: '#0f1318ff',
        panel_border: '#ffffff1a',
        sidebar_stroke: '#ffffff29',
        sidebar_fill: '#ffffff09',
        terminal_bg: '#0f1318ff',
        terminal_foreground: '#e7ebf2ff',
        terminal_cursor: '#e7ebf2cc',
        overlay_text: '#f0f0f0f5',
        overlay_subdued: '#c2c2c2f0',
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

const isRecord = (value: unknown): value is Record<string, any> =>
    typeof value === 'object' && value !== null && !Array.isArray(value)

const deepMerge = (base: Record<string, any>, override: Record<string, any>): Record<string, any> => {
    const merged: Record<string, any> = { ...base }
    for (const [key, value] of Object.entries(override))
        merged[key] = isRecord(base[key]) && isRecord(value) ? deepMerge(base[key], value) : value
    return merged
}

export const readConfig = async (): Promise<Record<string, any>> => {
    const file = Bun.file(path.join(os.homedir(), '.osm', 'osm.yaml'))
    if (!await file.exists()) return std
    const parsed = YAML.parse(await file.text())
    return deepMerge(std, isRecord(parsed) ? parsed : {})
}

const flatten = (obj: Record<string, any>, prefix = ''): string[] =>
    Object.entries(obj).flatMap(([k, v]) =>
        typeof v === 'object' && v !== null ? flatten(v, `${prefix}${k}.`) : [`${prefix}${k}=${v}`])

export const writeConfigFlat = async (cfg: Record<string, any>) =>
    writeFile(path.join(os.homedir(), '.osm', 'config'), flatten(cfg).join('\n') + '\n')
