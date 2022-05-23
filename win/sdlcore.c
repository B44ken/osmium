#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>
#include "text.h"
#include "ui.h"

SDL_Window* window;
SDL_Renderer* renderer;
TTF_Font* ui_font;
TTF_Font* editor_font;

void draw_rect(SDL_Rect rect, SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderFillRect(renderer, &rect);
    SDL_RenderPresent(renderer);
}

void draw_clear() {
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderClear(renderer);
}

void draw_ui(char* e) {
    editor = e;
    ui_draw_base(ui_font);
}
void sdl_init(SDL_Window* window, SDL_Renderer* g_renderer) {
    editor = malloc(1024);

    SDL_Init(SDL_INIT_EVERYTHING);
    window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 720, 540, 0);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    g_renderer = renderer;
    init_fonts(renderer);
    ui_font = make_font("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 14);
    editor_font = make_font("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 16);

    draw_clear();
    draw_ui("god");
}