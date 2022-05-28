typedef struct {
    FILE* file;
    char* name;
    char* editor;
    char mode;
    int cursor[2];
} tab;
extern tab* tab_list;
extern tab* tab_focused;
tab tab_editor();
void tab_list_make();