#include <SDL2/SDL.h>
#include <stdio.h>
#include "sdlcore.h"

char file[1024];
int cursor = 0;
int uppercase = 0;
void event_keypress(int key) { 
    if(key >= 20 && key <= 126) {
        file[cursor] = key;
        file[cursor+1] = 0;
        cursor++;
    }
    if(key == 8) {
        if(cursor > 0) {
            cursor--;
            file[cursor] = 0;
        }
    }
    draw_ui(file);
}

void event_handle() {
    SDL_Delay(1);
    SDL_Event event;
    int ok = SDL_PollEvent(&event);
    if(ok == 0) { return; }
    if(event.type == SDL_QUIT) {
        exit(0);
    }
    if(event.type == SDL_KEYDOWN) {
        event_keypress(event.key.keysym.sym);
    }

    return;
}