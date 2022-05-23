#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include "text.h"
#include <stdio.h>

SDL_Window* window;
SDL_Renderer* renderer;
TTF_Font* ui_font;
TTF_Font* editor_font;

void draw_rect(SDL_Rect rect, SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderFillRect(renderer, &rect);
}

void sdl_init(SDL_Window* window, SDL_Renderer* renderer) {
    SDL_Init(SDL_INIT_EVERYTHING);
    window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 720, 540, 0);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    init_fonts(renderer);
    ui_font = make_font("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 12);
    editor_font = make_font("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 14);
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderClear(renderer);

    draw_text("hello, world!", (SDL_Rect){50, 50}, (SDL_Color){0, 0, 0, 255}, ui_font);

    SDL_RenderPresent(renderer);
}