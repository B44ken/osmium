c:
	gcc win/*.c `sdl2-config --cflags --libs` -lSDL2_ttf -lSDL2_image -o osmium