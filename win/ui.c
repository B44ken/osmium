#include <SDL2/SDL_ttf.h>
#include "sdlcore.h"
#include "text.h"

void draw_base(TTF_Font* ui_font) {
    draw_rect((SDL_Rect){0, 0, 720, 540}, (SDL_Color){32, 32, 32, 255});
    draw_rect((SDL_Rect){0, 32, 720, 540}, (SDL_Color){16, 16, 16, 255});
    draw_rect((SDL_Rect){2, 2, 28, 28}, (SDL_Color){255, 255, 255, 255});
}