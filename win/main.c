#include <stdio.h>
#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

#include "font.h"

int main() {
	SDL_Init(SDL_INIT_VIDEO);
	SDL_Window* window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 640, 480, SDL_WINDOW_SHOWN);
	SDL_Surface* surface = SDL_GetWindowSurface(window);

	SDL_FillRect(surface, NULL, SDL_MapRGB(surface->format, 0, 0, 0));
	text_opt text = get_font("DejaVu Sans Mono", 24);

	SDL_Color white = {255, 255, 255};
	text.color = white;

	SDL_UpdateWindowSurface(window);

	SDL_Delay(500);

	SDL_Event event;
	while(1) {
		if(!SDL_PollEvent(&event)) { continue; }
		if(event.type == SDL_QUIT) { return; }
		if(event.type == SDL_KEYUP) { 
			text.x += 16;
			key = get_key(event.key.keysym);
			text.message = &key;

			if(key == 13) {
				text.x = 0;
				text.y += 30;
				continue;
			}
			if(key == 8) {
				text.x -= 16 * 2;
				if(text.x == -16) {
					text.x = 0;
					text.y -= 30;
				}
			}
			if(key <= 3

			render_font(surface, text);
			SDL_UpdateWindowSurface(window);
			SDL_Delay(1);
		}
	}

	SDL_DestroyWindow(window);
	SDL_Quit();
}
