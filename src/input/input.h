#pragma once

#include <SDL2/SDL.h>

#include "../editor/editor.h"

class InputManager {
    public:
    Editor* editor;
    void handleInput();  
};