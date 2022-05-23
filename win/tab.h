#include <stdio.h>

typedef struct {
    FILE* file;
    char* name;
    int mode;
    int cursor[2];
} tab;

tab editor_new(char* file);
