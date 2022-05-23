#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>

extern SDL_Renderer* renderer;

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
}

void draw_text(SDL_Rect pos, SDL_Color color, char* message, TTF_Font* font) {
    SDL_Surface* text_surface = TTF_RenderText_Blended(font, message, color);
    SDL_Texture* text_texture = SDL_CreateTextureFromSurface(renderer, text_surface);
    SDL_Rect dest = {pos.x, pos.y, text_surface->w, text_surface->h};
    SDL_RenderCopy(renderer, text_texture, NULL, &dest);
    SDL_RenderPresent(renderer);
}