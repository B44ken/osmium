# osmium

osmium is a nice minimalist shell & editor & stuff. the agent harness supports cladue & chatgpt subscriptions, plus custom openai endpoints. currently it supports mac.

https://github.com/user-attachments/assets/45b2af43-8a52-429a-8e30-2b74f2397556

## install

```bash
curl $something | install.sh
```

## use it
**non-obivous shortcuts**

`opt [` `opt ]` switch tabs

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

see `~/.osm/osm.yaml`. by default:

```yaml
options:
  start_dir: /users/brad/git
  font_mono: 'SF Mono'
  tabs_slide_ms: 90
  tabs_slide_delay: 90
  terminal:
    font_size: 16
  editor:
    font_size: 14

window:
  height: 600
  width: 900
  tabs_width: 280

agent:
  model: 'gpt-5.6'
  thinking: 'xhigh'
```
