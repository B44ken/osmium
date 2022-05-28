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
    if(tab_count == 32) {
        printf("too many tabs: %d\n", tab_count);
        return t;
    }
    t.name = file;
    t.file = fopen(t.name, "w+");
    if(t.file == NULL) {
        printf("failed to open: %s\n", t.file);
    }
    // while(fgets(t.editor, 2048, t.file) != EOF) {}
    system("sh -c 'echo hello! today is $(date -Idate) >> /tmp/osm/untitled1'");
    t.editor = realloc(t.editor, /*  */8192);
    char* file_error = fgets(t.editor, 64, t.file);
    if(file_error == NULL) {
        printf("?????\n");
    }
    t.mode = 'e';
    t.cursor[0] = strlen(t.editor);
    return t;
}

// tab* tab_terminal(char* file) {
//     tab t;
//     t.name = file;
//     t.mode = 't';
//     tab_focused = &t;
//     return &t;
// }

void tab_list_make() {
    tab_list = malloc(512);
    system("mkdir -p /tmp/osm/");
    tab_list[0] = tab_editor("/tmp/osm/untitled1");
    tab_focused = &tab_list[0];
    event_update_editor();
}