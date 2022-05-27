#include <SDL2/SDL_ttf.h>

TTF_Font* make_font();
void init_fonts();
void draw_text();

extern TTF_Font* editor_font;
extern TTF_Font* ui_font;