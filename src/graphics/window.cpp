#include <iostream>
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

#include "../editor/editor.h"
#include "../config/config.h"
#include "window.h"
#include "text.h"
#include "../editor/format.h"

Window::Window() {
    SDL_Init(SDL_INIT_VIDEO);
    TTF_Init();
    SDL_Window* window = SDL_CreateWindow("osmium", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 800, 600, SDL_WINDOW_SHOWN);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    this->window = window;
    this->renderer = renderer;
}

void Window::applyConfig(nlohmann::json* config) {
    this->config = config;
    std::string editorFontPath = (*config)["editorFontPath"];
    std::string uiFontPath = (*config)["uiFontPath"];
    int fontSize = (*config)["fontSize"];
    editorFont = new Font(editorFontPath, fontSize);
    uiFont = new Font(uiFontPath, fontSize);
}

void Window::drawDebugText() {
    drawEditorText();
}

int Window::getLineLength() {
    int windowWidth, charWidth;
    SDL_GetWindowSize(window, &windowWidth, NULL);
    TTF_SizeText(editorFont->font, "a", &charWidth, NULL);
    return windowWidth / charWidth;
}

void Window::drawEditorText() {
    editor->lineLength = getLineLength();
    editorFont->drawText(window, renderer, editor->outputFormatted());
}

void Window::finish() {
    SDL_RenderPresent(renderer);
}

void Window::drawCursor() {
    // this snippet is comically ugly and doesn't even work
    std::string currentLine = wordWrapLine(editor->lines[editor->cursor[1]], editor->lineLength).substr(0, editor->cursor[0] + 1);
    int finalLength = currentLine.length() - currentLine.find_last_of("\n");
    int newlines = std::count(currentLine.begin(), currentLine.end(), '\n');

    int fontWidth, fontHeight;
    TTF_SizeText(editorFont->font, "a", &fontWidth, &fontHeight);

    int wrapped[2];
    wrapped[1] = editor->cursor[1] + newlines;
    wrapped[1] *= fontHeight;
    wrapped[0] = finalLength - 2 + newlines;
    wrapped[0] *= fontWidth;

    SDL_Rect cursor = {wrapped[0], wrapped[1] + 2, 2, TTF_FontHeight(editorFont->font) - 2};
    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
    SDL_RenderFillRect(renderer, &cursor);
}

void Window::clear() {
    std::vector<uint64_t> bgColor = (*config)["backgroundColor"];
    
    SDL_SetRenderDrawColor(renderer, bgColor[0], bgColor[1], bgColor[2], 255);
    SDL_RenderClear(renderer);
}