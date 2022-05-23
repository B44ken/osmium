typedef struct {
    int x;
    int y;
    char* message;
    SDL_Color color;
    TTF_Font* font;
} text_opt;

text_opt get_font(char* name, int size);
int render_font(SDL_Surface* surface, text_opt text);