import { YAML } from 'bun'
import { readFileSync, existsSync } from 'node:fs'
import { homedir } from 'node:os'

type Cfg = {
    font: { mono: string; sans: string; size: number; sizes: Record<string, number> }
    agent: { permissions: string; effort: string; model: string }
    window: { width: number; height: number; sidebar: { width: number; slidedelay: number; slideduration: number } }
}

const deep = (base: any, over: any): any => {
    if (base?.constructor !== Object || over?.constructor !== Object) return over
    const out = { ...base }
    // an emptied key ("width:") parses as null — no override, keep the repo default underneath
    for (const k in over) if (over[k] != null) out[k] = deep(base[k], over[k])
    return out
}

// yaml's empty document parses as null, which would poison the merge — treat it as an empty mapping
const read = (path: string) => (existsSync(path) ? YAML.parse(readFileSync(path, 'utf8')) : null) ?? {}

// repo osm.yaml is tracked defaults; ~/.osm/osm.yaml is this machine's overrides and keys
export const load = () => deep(
    read(`${import.meta.dir}/../osm.yaml`),
    read(`${homedir()}/.osm/osm.yaml`),
) as Cfg

export default load()
