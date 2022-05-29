#include <stdio.h>
#include "tab.h"

int file_open(char* file, char* buf) {
}

int file_save(tab* tab_editor) {
    fseek(tab_editor->file, 0, SEEK_SET);
    int file_err = fputs(tab_editor->editor, tab_editor->file);
    if(file_err == 0) {
        printf("failed to save: %s\n", tab_editor->name);
        return 1;
    }
    fflush(tab_editor->file);
    return 0;
}