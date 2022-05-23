#include <SDL2/SDL.h>
#include "sdlcore.h"
#include "event.h"
// #include "text.h"
// #include "tabs.h"

int main(int argc, char** argv) {
    sdl_init();

    while(1) {
        event_handle();
    }

    return 0;
//     terminal_new();
//     tabs_init();
//     handle_events();
}
