#include <SDL2/SDL_ttf.h>
#include "draw.h"
#include "tab.h"

extern SDL_Window* window;
extern TTF_Font* ui_font;
extern TTF_Font* editor_font;
SDL_Rect rect;
int win_width = 720;
int win_height = 540;

SDL_Color grey = {210, 210, 210, 255};
SDL_Color black = {30, 30, 30, 255};
SDL_Color white = {240, 240, 240, 255};

void ui_draw_tabs() {
    for(int i = 1; i < tab_count; i++) {
        if(tab_focused == &tab_list[i]) { }
            draw_rect((SDL_Rect){(i-1)*140+2, 2, 136, 28}, white);/*  */
            draw_text((SDL_Rect){(i-1)*140+4, 2}, black, tab_list[i].name, ui_font);
    }
}

void ui_draw_base() {
    SDL_GetWindowSize(window, &win_width, &win_height);    
    draw_clear();
    draw_rect((SDL_Rect){0, 0, win_width, win_height}, grey);
    draw_rect((SDL_Rect){0, 32, win_width, win_height-32}, black);
    draw_rect((SDL_Rect){win_width-134, 2, 28, 28}, white);
    draw_rect((SDL_Rect){win_width-104, 2, 100, 28}, white);
    draw_text((SDL_Rect){2, 32}, white, tab_focused->editor, editor_font);
    draw_text((SDL_Rect){win_width-124, 4, 28, 28}, black, "+", ui_font);
    draw_text((SDL_Rect){win_width-100, 4}, black, "settings", ui_font);
    ui_draw_tabs();
}

