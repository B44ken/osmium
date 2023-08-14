#include <SDL2/SDL.h>

#include "input.h"

void InputManager::handleInput() {
    SDL_Event event;
    while(SDL_PollEvent(&event)) {
        if(event.type == SDL_QUIT) {
            SDL_Quit();
            exit(0);
        } else if(event.type == SDL_KEYDOWN) {
            int key = event.key.keysym.sym;
            int mod = event.key.keysym.mod;
            editor->handleInput(key, mod);
        }
    }
}