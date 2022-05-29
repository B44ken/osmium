#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "event.h"

typedef struct {
    FILE* file;
    char* name;
    char* editor;
    char mode;
    int cursor[2];
} tab;

tab* tab_list;
tab* tab_focused;
int tab_count = 0;

tab tab_editor(char* file) {
    tab t;
    t.name = file;

    char touch_cmd[256] = "touch ";
    strcat(touch_cmd, t.name);
    system(touch_cmd);

    t.file = fopen(t.name, "r+");
    if(t.file == NULL) {
        printf("failed to open: %s\n", t.file);
    }
    fseek(t.file, 0, SEEK_END);
    int file_size = ftell(t.file);
    fseek(t.file, 0, SEEK_SET);
    t.editor = malloc(file_size + 8192);
    fread(t.editor, file_size, 1, t.file);
    
    t.mode = 'e';
    t.cursor[0] = strlen(t.editor);

    return t;
}

void tab_open_editor(char* name) {
    tab_list[tab_count] = tab_editor(name);
    tab_focused = &tab_list[tab_count];
    tab_count++;
    event_update_editor();
}

void tab_list_make() {
    tab_list = malloc(512);
    system("mkdir -p /tmp/osm/");
    if(tab_count == 0) {
        tab_open_editor("/tmp/osm/untitled");
    }
    event_update_editor();
}