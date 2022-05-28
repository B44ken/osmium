flags=`sdl2-config --cflags --libs` -lSDL2_ttf -lSDL2_image -I"./src/h/"
winflags=-L/opt/local/x86_64-w64-mingw32/lib -lmingw32 -mwindows -I/opt/local/x86_64-w64-mingw32/include -Dmain=SDL_main -lSDL2main -lSDL2 -lSDL2_ttf
linux: build c go

build:
	mkdir -p build
c:
	gcc src/*.c $(flags) -o build/osmium

cwin:
	x86_64-w64-mingw32-gcc src/*.c $(flags) -o osmium.exe

go:
	GOOS='linux' go build util/tree.go
	mv tree* build/osmtree