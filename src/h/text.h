#include <string>
#include <vector>

class EditorText {
    public:
    std::vector<std::string> lines;
    std::string path;
    std::string render(int columns, int scroll);
    int cursor[2];
};

std::string wordWrap(std::string line, int softMax, int max);