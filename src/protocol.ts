export type Command = { cwd?: string } &
     ({ type: "open-terminal" }
    | { type: "open-editor"; path: string; }
    | { type: "open-browser"; url: string; }
    | { type: "add-bind"; event: string; command: string; })
