flags=`sdl2-config --cflags --libs` -lSDL2_ttf -I"./src/h/"
mingw=/opt/local/x86_64-w64-mingw32/
winflags=-L$(mingw)lib -lmingw32 -mwindows -I$(mingw)include -I"./src/h/" -Dmain=SDL_main -lSDL2main -lSDL2 -lSDL2_ttf

linux: build c go
win: buildwin cwin gowin
build:
	mkdir -p build
buildwin:
	mkdir -p build
	cp $(mingw)bin/SDL2.dll build
	cp $(mingw)bin/SDL2_ttf.dll build
c:
	gcc src/*.c $(flags) -o build/osmium
cwin:
	x86_64-w64-mingw32-gcc src/*.c $(winflags) -o build/osmium.exe
go:
	GOOS='linux' go build -o build/osmutil util/*.go
gowin:
	GOOS='linux' go build -o build/osmutil.exe util/*.go
debug: c
	gcc -g src/*.c $(flags) -o build/osmium
	gdb -ex run --args build/osmium /tmp/osm/untitled1
