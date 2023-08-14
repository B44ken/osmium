#pragma once

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

#include "../editor/editor.h"
#include "../config/config.h"
#include "text.h"

class Window {
    public:
    Window();
    void drawDebugText();
    void drawEditorText();
    void drawAll();
    void clear();
    void finish();
    void drawCursor();
    void applyConfig(nlohmann::json* config);
    int getLineLength();
    SDL_Renderer* renderer;
    SDL_Window* window;
    Font* editorFont;
    Font* uiFont;
    Editor* editor;
    nlohmann::json* config;
};