#include <SDL2/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include "tab.h"
#include "draw.h"
#include "file.h"

SDL_Event event;
char* editor;
int editorsize = 4096;
int* cursor = 0;

void event_update_editor() {
    cursor = tab_focused->cursor;
    editor = tab_focused->editor;
}

void event_type(char key) {
    if((key >= 20 && key <= 126) || key == '\n') {
        editor[cursor[0]] = key;
        editor[cursor[0]+1] = 0;
        cursor[0]++;
    }

    if(cursor[0]*2 > editorsize) {
        editorsize *= 2;
        editor = realloc(editor, editorsize);
    }
}
void event_key(char key) {
    if(key == 13) {
        event_type('\n');
    }
    if(key == 8) {
        editor[cursor[0]] = 0;
        if(cursor[0] > 0) {
            cursor[0]--;
        }
    }
}

void event_button(int x, int y, int which) {
    if(y > 32) { return; }
    int fromback = win_width - x;
    if(fromback > 140) {
        int tabn = x / 140;
        if(tabn < tab_count) {
            tab_focused = &tab_list[tabn];
            event_update_editor();
            printf("button pressed: %d\n", tabn);
        }
        return;
    }
    if(fromback < 100) {
        printf("button pressed: settings\n");
        return;
    }
    if(fromback < 140) {
        tab_open_editor("/tmp/osm/untitled");
        return;
    }
}

void event_shortcut(char key) {
        if(key == 's') {
            file_save(tab_focused);
        } else if(key == 'o') {
            // tab_open_editor("/tmp/osm/untitled");
        } else if(key == 'q') {
            // tab_close(tab_focused);
        }
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
            event_shortcut(key);
        } else {
            event_key(event.key.keysym.sym);
        }
    } else if(event.type == SDL_MOUSEBUTTONUP) {
        event_button(event.button.x, event.button.y, event.button.button);
    }

    draw_ui(editor);
    return;
}
