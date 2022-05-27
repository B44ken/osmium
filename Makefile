sdlflags=`sdl2-config --cflags --libs` -lSDL2_ttf -lSDL2_image
sdlwinflags=-L/opt/local/x86_64-w64-mingw32/include -Dmain=SDL_main -I/opt/local/x86_64-w64-mingw32/lib -lmingw32 -mwindows
sdlwinflags=-L/opt/local/x86_64-w64-mingw32/lib -lmingw32 -mwindows -I/opt/local/x86_64-w64-mingw32/include -Dmain=SDL_main -lSDL2main -lSDL2 -lSDL2_ttf
c:
	gcc src/*.c $(sdlflags) -o osmium

cwin:
	x86_64-w64-mingw32-gcc src/*.c $(sdlwinflags) -o osmium.exe
