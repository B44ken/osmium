#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include "sdlcore.h"

char* file;
int filesize = 4096;
int cursor = 0;
int uppercase = 0;
void event_key(int key) { 
    if(cursor == 0) {
        file = malloc(filesize);
    }
    if(key == 13) {
        key == '\n';
        cursor++;
    }
    if(key >= 20 && key <= 126) {
        file[cursor+1] = 0;
        cursor++;
    }
    if(key == 8) {
        if(cursor > 0) {
            cursor--;
            file[cursor] = 0;
        }
    }
    if(cursor*2 > filesize) {
        filesize *= 2;
        file = realloc(file, filesize);
        printf("realloc(%d)\n", filesize);
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
    } else if(event.type == SDL_TEXTINPUT) {
	printf("text key: %d from  %s\n", event.text.text[0], event.text.text);
        event_key(event.text.text[0]);
    } else if(event.type == SDL_KEYDOWN) {
        event_key(event.key.keysym.sym);
    }

    return;
}
