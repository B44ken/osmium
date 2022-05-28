#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include "tab.h"
#include "draw.h"

SDL_Event event;
char* editor;
int editorsize = 4096;
int cursor = 0;
extern int win_width;


void event_update_editor() {
    cursor = tab_focused->cursor[0];
    editor = tab_focused->editor;
}

void event_type(char key) {
    if((key >= 20 && key <= 126) || key == '\n') {
        editor[cursor] = key;
        editor[cursor+1] = 0;
        cursor++;
    }

    if(cursor*2 > editorsize) {
        editorsize *= 2;
        editor = realloc(editor, editorsize);
    }

}
void event_key(char key) {
    if(key == 13) {
        event_type('\n');
    }
    if(key == 8) {
        editor[cursor] = 0;
        if(cursor > 0) {
            cursor--;
        }
    }
}

void event_button(int x, int y, int which) {
    if(y > 32) { return; }
    int fromback = win_width - x;
    if(win_width - x > 160) {
        int tabn = x / 160;
        printf("button pressed: %d\n", tabn);
        return;
    }
    if(fromback < 100) {
        printf("button pressed: settings\n");
        return;
    }
    printf("button pressed: +\n");
}

void event_handle() {
    int ok = SDL_PollEvent(&event);
    if(ok == 0) { return; }
    if(event.type == SDL_QUIT) {
        exit(0);
    } else if(event.type == SDL_TEXTINPUT) {
        event_type(event.text.text[0]);
    } else if(event.type == SDL_KEYDOWN) {
        char key = event.key.keysym.sym;
        if(event.key.keysym.mod & KMOD_LCTRL && key != -32) {
            printf("ctrl + %d\n", key);
        }
        event_key(event.key.keysym.sym);
    } else if(event.type == SDL_MOUSEBUTTONUP) {
        event_button(event.button.x, event.button.y, event.button.button);
    }

    draw_ui(editor);
    return;
}
