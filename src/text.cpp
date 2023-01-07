#include <string>
#include <vector>

std::string wordWrap(std::string line, int softMax, int max) {
    std::string output;
    int currentLineLength = 0;
    output += line[0];
    for(int i = 1; i < line.length(); i++) {
        currentLineLength++;
        if(currentLineLength >= softMax && line[i] == ' ') {
            output += "\n";
            currentLineLength = 0;
        } else if (currentLineLength >= max) {
            output += "\n";
            output += line[i];
            currentLineLength = 0;
        } else {
            output += line[i];
        }
    }
    return output;
}

class EditorText {
    public:
    std::vector<std::string> lines;
    std::string path;
    std::string render(int columns, int scroll);
    int cursor[2];
};

std::string EditorText::render(int columns, int scroll) {
    std::string output;
    for(int i = scroll; i < lines.size() + scroll; i++) {
        output += wordWrap(lines[i], columns, columns);
        output += "\n";
    }
    if(output.length() > 0)
        output.pop_back();
    return output;
}
