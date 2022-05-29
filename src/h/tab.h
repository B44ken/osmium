#include <stdio.h>

typedef struct {
    FILE* file;
    char* name;
    char* editor;
    char mode;
    int cursor[2];
} tab;
extern int tab_count;
extern tab* tab_list;
extern tab* tab_focused;
tab tab_editor();
tab* tab_open_editor(char* name);
void tab_list_make();