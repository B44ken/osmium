#include <stdio.h>
#include <strings.h>
#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

int ttf_init_done = 0;

typedef struct {
    int x;
    int y;
    char* message;
    SDL_Color color;
    TTF_Font* font;
} text_opt;


// linux: fc-list
text_opt get_font(char* name, int size) {
    if(ttf_init_done == 0) {
        TTF_Init();
        ttf_init_done = 1;
    }

    char* font_name;
    if(strcmp(name, "DejaVu Sans")) {
        font_name = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";
    }

    SDL_Color black = {0, 0, 0};

    text_opt base;
    base.font = TTF_OpenFont(font_name, size);
    base.color = black;
    base.message = "<empty>";
    base.x = 0;
    base.y = 0;
    return base;
}

int render_font(SDL_Surface* surface, text_opt text) {
    SDL_Rect position = {text.x, text.y, 0, 0};
    SDL_Surface* text_surface = TTF_RenderText_Solid(text.font, text.message, text.color);
    SDL_BlitSurface(text_surface, NULL, surface, &position);
    SDL_FreeSurface(text_surface);
}