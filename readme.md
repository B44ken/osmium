# osmium

osmium is a nice minimalist shell & editor & stuff. the agent harness supports claude, github copilot & chatgpt subscriptions, plus custom openai endpoints. currently it supports mac.

https://github.com/user-attachments/assets/45b2af43-8a52-429a-8e30-2b74f2397556

## install

```bash
curl $something | install.sh
```

## use it
**non-obivous shortcuts**

`opt [` `opt ]` switch tabs

`opt =` `opt -` font size for the current pane type, saved to `~/.osm/osm.yaml`

**from the terminal**

```bash
# new terminal
osm 

# new text editor
osm edit ~/.osm/osm.yaml

# new browser
osm web github.com

# new agent
osm agent
```

**settings**

config is `osm.yaml` at the repo root (tracked defaults), with `~/.osm/osm.yaml`
deep-merged over top of it for machine-local overrides and api keys. keys stay out
of the repo. the defaults:

```yaml
font:
  mono: 'Menlo'
  sans: 'Inter'
  size: 14          # fallback for panes with no entry below
  sizes:            # per-pane, falls back to font.size
    term: 15
    edit: 14
    agent: 14
window:
  width: 900
  height: 600
  sidebar:
    width: 250
    slidedelay: 0.12
    slideduration: 0.06
agent:
  permissions: 'auto'
  effort: 'xhigh'
  model: 'claude/opus'
  keys: {}          # real keys live in ~/.osm/osm.yaml
```

`agent.model` is `provider/model`. `copilot/*` runs on your copilot subscription
(`copilot/claude-sonnet-4.6`, `copilot/gpt-5.6-sol`, ...), `claude/*` on your claude
subscription, `cohere/*` on cohere, and anything else goes to openrouter using its
own `vendor/model` ids.
