#include <fstream>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL.h>
#include <string>

class Window {
    public:
    Window(const char* title, int width, int height);
    void drawText(std::string text);
    void destroy();
    void setBackground(SDL_Color color);
    SDL_Window* window;
    SDL_Renderer* renderer;
    TTF_Font* editorFont;
};

void Window::setBackground(SDL_Color color) {
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderClear(renderer);
    SDL_RenderPresent(renderer);
}

Window::Window(const char* title, int width, int height) {
    SDL_Init(SDL_INIT_EVERYTHING);
    window = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height, SDL_WINDOW_SHOWN);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    editorFont = TTF_OpenFont("c:/windows/fonts/consola.ttf", 16);
    SDL_FillRect(SDL_GetWindowSurface(window), NULL, SDL_MapRGB(SDL_GetWindowSurface(window)->format, 255, 255, 255));
}

void Window::destroy() {
    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
}

void Window::drawText(std::string text) {
    TTF_Init();
    SDL_Color color = { 0, 255, 0 };
    SDL_Surface* surface = TTF_RenderText_Solid(editorFont, text.c_str(), color);
    SDL_Texture* texture = SDL_CreateTextureFromSurface(renderer, surface);
    SDL_Rect rect;
    rect.x = 0;
    rect.y = 0;
    rect.w = surface->w;
    SDL_RW
    rect.h = surface->h;
    SDL_RenderCopy(renderer, texture, NULL, &rect);
    SDL_RenderPresent(renderer);
}