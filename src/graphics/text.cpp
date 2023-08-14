#include <iostream>

#include "text.h"
#include "window.h"

Font::Font(std::string path, int size) {
    font = TTF_OpenFont(path.c_str(), size);
}

void Font::drawText(SDL_Window* window, SDL_Renderer* renderer, std::string text) {
    SDL_Color color = {255, 255, 255};
    SDL_Surface* surface = TTF_RenderText_Blended_Wrapped(font, text.c_str(), color, 8192);
    SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
    SDL_FreeSurface(surface);
    SDL_Rect rect = {0, 0, 0, 0};
    SDL_QueryTexture(texture, NULL, NULL, &rect.w, &rect.h);
    SDL_RenderCopy(renderer, texture, NULL, &rect);
    SDL_DestroyTexture(texture);
}