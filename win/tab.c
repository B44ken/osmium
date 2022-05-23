#include <stdio.h>

typedef struct {
    FILE* file;
    char* name;
    int mode;
    int cursor[2];
} tab;

tab tab_list[16];

tab editor_new(char* file) {
    tab edit;
    if(file == "") {
        file = "/tmp/osm-untitled";
    }
    edit.file = fopen(file, "wr");
    edit.name = file;
    edit.mode = 0;

    tab_list[0] = edit;

    return edit;
}

