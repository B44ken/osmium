#include <string>

class Tab {
};

class Editor : public Tab {
    public:
    void loadFile(std::string file);
    void saveFile();
    void close();
    void renderText();
    void handleInput();
    std::string fileName;
    std::string fileContents;
};

class Terminal : public Tab {
    public:
    void close();
    void render();
    void handleInput();
    std::string root;
};