#pragma once

#include <string>

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

class Font {
    public:
    Font(std::string path, int size);
    void drawText(SDL_Window* window, SDL_Renderer* renderer, std::string text);
    TTF_Font* font;
};