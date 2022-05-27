#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>
#include "text.h"
#include "ui.h"

SDL_Window* window;
SDL_Renderer* renderer;

void draw_rect(SDL_Rect rect, SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderFillRect(renderer, &rect);
}

void draw_clear() {
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderClear(renderer);
}

void draw_ui(char* e) {
    editor = e;
    ui_draw_base(ui_font);
    SDL_Delay(1);
    SDL_RenderPresent(renderer);
}
void sdl_init(SDL_Window* window, SDL_Renderer* g_renderer) {
    SDL_Init(SDL_INIT_EVERYTHING);
    SDL_StartTextInput();
    window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 720, 540, SDL_WINDOW_RESIZABLE);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    g_renderer = renderer;
    init_fonts(renderer);
    #ifdef _WIN64
        ui_font = make_font("c:/windows/fonts/trebuc.ttf", 14);
        editor_font = make_font("c:/windows/fonts/consola.ttf", 16);
    #elif __linux__
        ui_font = make_font("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 14);
        editor_font = make_font("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 16);
    #endif
    draw_clear();
    draw_ui("");
}
