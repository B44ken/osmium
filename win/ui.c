#include <SDL2/SDL_ttf.h>
#include "sdlcore.h"
#include "text.h"

char* editor;
extern TTF_Font* editor_font;
extern TTF_Font* ui_font;

void ui_draw_base() {
    draw_clear();
    draw_rect((SDL_Rect){0, 0, 720, 540}, (SDL_Color){32, 32, 32, 255});
    draw_rect((SDL_Rect){0, 32, 720, 540}, (SDL_Color){16, 16, 16, 255});
    draw_rect((SDL_Rect){2, 2, 190, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){4,4}, (SDL_Color) {0, 0, 0, 255}, "/tmp/osm/untitled1", ui_font);
    draw_rect((SDL_Rect){600, 2, 28, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){608, 4}, (SDL_Color) {0, 0, 0, 255}, "+", ui_font);
    draw_rect((SDL_Rect){636, 2, 100, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){640, 4}, (SDL_Color) {0, 0, 0, 255}, "settings", ui_font);
    if(editor[0] != 0) {
        draw_text((SDL_Rect){2, 32}, (SDL_Color) {200, 200, 200, 255}, editor, editor_font);
    }
}