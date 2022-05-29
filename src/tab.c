#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "event.h"
#include "file.h"

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
    t.mode = 'e';
    file_open(&t);
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