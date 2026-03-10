export type AppCommand = { cwd?: string } &
     ({ type: "open-terminal" }
    | { type: "open-agent"; }
    | { type: "open-editor"; path: string; }
    | { type: "open-browser"; url: string; }
    | { type: "add-bind"; event: string; command: string; })

export type Command = AppCommand
