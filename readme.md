# osmium

osmium is a nice minimalist shell & editor & stuff. agents use your subscription (claude or codex) through acp. currently, it supports mac.

https://github.com/user-attachments/assets/45b2af43-8a52-429a-8e30-2b74f2397556

## install

```bash
curl $something | install.sh
```

## use it
**non-obivous shortcuts**

`opt [` `opt ]` switch tabs

`opt -` `opt +` font size for the current pane

**from the terminal**

```bash
# new terminal
osm 

# new text editor
osm edit ~/.osm/osm.yaml

# new browser
osm web github.com
osm web ./index.html

# new agent
osm agent
```

**settings**

edit `~/.osm/osm.yaml` to change these. for example:

```yaml
font:
  mono: 'Menlo'
  sans: 'Inter'
  sizes:
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
  permissions: 'auto' # or `ask` or `bypass`
  effort: 'xhigh'
  model: 'codex/gpt-6-sol' # format is `provider/model`
```
