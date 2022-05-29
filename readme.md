# osmuim

[hello screenshot](docs/hello.png)

osmium is a text editor. i wanted it to:
- start quickly
- run on at least windows and linux
- support running processes (`python`, `bash`...)
- be customizable
- not make me want to vomit (syntax highlighting, word wrap...)

## installing
requires sdl2, sdl_ttf, c (gcc/mingw), go

`make linux` or `make win`

for windows builds, make sure you have [sdl](https://github.com/libsdl-org/SDL/releases/) and [sdl2_ttf](https://github.com/libsdl-org/SDL_ttf/releases/) copied to `/opt/local/x86_64-w64-mingw32/`