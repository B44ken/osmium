#include <SDL2/SDL.h>

class Window {
    public:
    Window(const char* title, int width, int height);
    void destroy();
    void drawText(std::string text);
    void setBackground(SDL_Color color);
    SDL_Window* window;
    SDL_Renderer* renderer;
};