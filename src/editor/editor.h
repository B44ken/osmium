#pragma once

#include <string>
#include <vector>

#include "../tab/tab.h"

class Editor {
    public:
    Editor();
    void loadFile(std::string file);
    void handleInput(int key, int mod);
    std::vector<std::string> lines;
    std::string outputFormatted();
    std::vector<std::vector<int>> wrapMarkers;
    int lineLength;
    int cursor[2] = {0, 0};
};
