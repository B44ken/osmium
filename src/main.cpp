#include <string>
#include <vector>
#include <iostream>

// #include "tab/tab.h"
#include "config/config.h"
#include "editor/editor.h"
#include "graphics/window.h"
#include "input/input.h"

int main(int argv, char** args) {
    Window demoWindow;
    Editor demoEditor;
    Config config;
    InputManager inputs;

    demoWindow.editor = &demoEditor;
    inputs.editor = &demoEditor;
    demoWindow.applyConfig(&config.config);

    demoEditor.loadFile("/mnt/c/dev/osmium/hoopsnake.txt");

    while(true) {
        inputs.handleInput();
        demoWindow.clear();
        demoWindow.drawEditorText();
        demoWindow.drawCursor();
        demoWindow.finish();
    }

    return 0;
}