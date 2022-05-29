#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "tab.h"

void file_open(tab* t) {
    char touch_cmd[256] = "touch ";
    strcat(touch_cmd, t->name);
    system(touch_cmd);

    t->file = fopen(t->name, "r");
    if(t->file == NULL) {
        printf("failed to open: %s\n", t->name);
    }
    fseek(t->file, 0, SEEK_END);
    int file_size = ftell(t->file);
    fseek(t->file, 0, SEEK_SET);
    t->editor = malloc(file_size + 8192);
    fread(t->editor, file_size, 1, t->file);
}

int file_save(tab* t) {
    FILE* file_out = fopen(t->name, "w");
    fseek(t->file, 0, SEEK_SET);
    int file_err = fputs(t->editor, file_out);
    if(file_err == 0) {
        printf("failed to save: %s\n", t->name);
        return 1;
    }
    fflush(file_out);
    file_open(t);
    return 0;
}