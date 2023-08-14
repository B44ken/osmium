#include <string>
#include <vector>
#include <iostream>
#include <fstream>

#include <SDL2/SDL.h>

#include "editor.h"

Editor::Editor() {}

void Editor::loadFile(std::string file) {
    std::ifstream fileStream(file);
    std::string line;
    while (std::getline(fileStream, line)) {
        lines.push_back(line);
    }
    fileStream.close();
}

void Editor::handleInput(int key, int mod) {
    if(('a' <= key && key <= 'z') || ('0' <= key && key <= '9') || key == ' ') {
        if(mod & KMOD_SHIFT) {
            key = toupper(key);
        }
        std::string line = lines[cursor[1]];
        line.insert(cursor[0], 1, key);
        lines[cursor[1]] = line;
        cursor[0]++;
    } else if (key == SDLK_BACKSPACE) {
        if(cursor[0] == 0) {

        } else {
            std::string line = lines[cursor[1]];
            line.erase(cursor[0] - 1, 1);
            lines[cursor[1]] = line;
            cursor[0]--;
        }
    } else if(key == SDLK_UP) {
        cursor[1] = std::max(cursor[1] - 1, 0);
    } else if(key == SDLK_DOWN) {
        cursor[1] = std::min(cursor[1] + 1, (int)lines.size() - 1);
    } else if(key == SDLK_LEFT) {
        cursor[0] = std::max(cursor[0] - 1, 0);
    } else if(key == SDLK_RIGHT) {
        cursor[0] = std::min(cursor[0] + 1, (int)lines[cursor[1]].size());
    }
}