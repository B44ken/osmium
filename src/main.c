#include <SDL2/SDL.h>
#include "sdlcore.h"
#include "event.h"

int main(int argc, char** argv) {
    sdl_init();
    while(1) {
        event_handle();
    }
}
