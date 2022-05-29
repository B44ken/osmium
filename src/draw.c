#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>
#include "ui.h"

TTF_Font* editor_font;
TTF_Font* ui_font;
int last_frame = 0;
int frametime = 1000/60;
extern SDL_Renderer* renderer;
extern char* editor;

TTF_Font* make_font(char* name, int size) {
    TTF_Font* font = TTF_OpenFont(name, size);
    if (font == NULL) {
        printf("sdl_ttf error: %s\n", TTF_GetError());
        return 0;
    }
    return font;
}

void init_fonts() {
    TTF_Init();
    #ifdef _WIN64
        ui_font = make_font("c:/windows/fonts/trebuc.ttf", 14);
        editor_font = make_font("c:/windows/fonts/consola.ttf", 16);
    #elif __linux__
        ui_font = make_font("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf", 14);
        editor_font = make_font("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf", 16);
    #endif
}

void draw_rect(SDL_Rect rect, SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderFillRect(renderer, &rect);
}

void draw_clear() {
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderClear(renderer);
}

int draw_ui() {
    if(last_frame + frametime > SDL_GetTicks()) {
        return 1;
    }
    last_frame = SDL_GetTicks();
    ui_draw_base(ui_font);
    SDL_RenderPresent(renderer);
    return 0;
}

void draw_text(SDL_Rect pos, SDL_Color color, char* message, TTF_Font* font) {
    if(message[0] == 0) { return; }
    SDL_Surface* text_surface = TTF_RenderText_Blended_Wrapped(font, message, color, 720);
    SDL_Texture* text_texture = SDL_CreateTextureFromSurface(renderer, text_surface);
    SDL_Rect dest = {pos.x, pos.y, text_surface->w, text_surface->h};
    SDL_RenderCopy(renderer, text_texture, NULL, &dest);
}