#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>

SDL_Renderer* ttf_renderer;

TTF_Font* make_font(char* name, int size) {
    TTF_Font* font = TTF_OpenFont(name, size);
    if (font == NULL) {
        printf("sdl_ttf error: %s\n", TTF_GetError());
        return 0;
    }
    return font;
}

void init_fonts(SDL_Renderer* renderer) {
    TTF_Init();
    ttf_renderer = renderer;
}

// void draw_text(char* text, SDL_Rect pos, TTF_Font* font, SDL_Color color) {
void draw_text(char* message, SDL_Rect pos, SDL_Color color, TTF_Font* font) {
    SDL_Surface* text_surface = TTF_RenderText_Solid(font, message, color);
    SDL_Texture* text_texture = SDL_CreateTextureFromSurface(ttf_renderer, text_surface);
    SDL_Rect dest = {pos.x, pos.y, text_surface->w, text_surface->h};
    int err = SDL_RenderCopy(ttf_renderer, text_texture, NULL, &dest);
}  