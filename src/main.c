#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <stdio.h>
#include <string.h>
#include "draw.h"
#include "ui.h"
#include "event.h"
#include "tab.h"

SDL_Window* window;
SDL_Renderer* renderer;
int flag_kill = 0;
extern int tab_count;

void init() {
    tab_list_make();
    SDL_Init(SDL_INIT_EVERYTHING);
    SDL_StartTextInput();
    window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 720, 540, SDL_WINDOW_RESIZABLE);
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    init_fonts(renderer);
    draw_ui("");
}

int main(int argc, char** argv) {
    init();

    for(int i = 1; i < argc; i++) {
        if(argv[i][0] == '-') {
            if(strcmp(argv[i], "--kill") == 0) {
                flag_kill = 1;
            }
        } else {
            tab_open_editor(argv[i]);
            printf("opening %s, no %d\n", argv[i], tab_count);
        }
    }

    while(1) {
        event_handle();
        if(flag_kill) {
            break;
        }
    }
}