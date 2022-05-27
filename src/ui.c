#include <SDL2/SDL_ttf.h>
#include "sdlcore.h"
#include "text.h"

extern SDL_Window* window;
char* editor;
SDL_Rect rect;
int win_width = 720;
int win_height = 540;

void ui_draw_base() {
    SDL_GetWindowSize(window, &win_width, &win_height);    
    draw_clear();
    draw_rect((SDL_Rect){0, 0, win_width, win_height}, (SDL_Color){32, 32, 32, 255});
    draw_rect((SDL_Rect){0, 32, win_width, win_height-32}, (SDL_Color){16, 16, 16, 255});
    draw_rect((SDL_Rect){2, 2, 160, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){4,4}, (SDL_Color) {0, 0, 0, 255}, "/tmp/osm/untitled1", ui_font);
    draw_rect((SDL_Rect){win_width-120, 2, 28, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){win_width-148, 4}, (SDL_Color) {0, 0, 0, 255}, "+", ui_font);
    draw_rect((SDL_Rect){win_width-104, 2, 100, 28}, (SDL_Color){200, 200, 200, 255});
    draw_text((SDL_Rect){win_width-100, 4}, (SDL_Color) {0, 0, 0, 255}, "settings", ui_font);
    if(editor[0] != 0) {
        draw_text((SDL_Rect){2, 32}, (SDL_Color) {200, 200, 200, 255}, editor, editor_font);
    }
}
