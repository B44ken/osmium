export type AppCommand = { cwd?: string } &
     ({ type: "open-terminal" }
    | { type: "open-agent"; }
    | { type: "open-editor"; path: string; hot?: string; }
    | { type: "open-browser"; url: string; })

export type Command = AppCommand
