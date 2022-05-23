#include <SDL.h>

char get_key(SDL_Keysym sym) {
    char key = sym.sym;
    // is ascii?
    if(key >= 32 && key <= 126) {
        return key;
    }
    else return ' ';
}