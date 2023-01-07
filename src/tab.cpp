#include <string>
#include <fstream>
#include <vector>

class Tab {
    public:
    bool open(std::string path);
    void close();
    std::string name;
    std::ifstream file;
};

bool Tab::open(std::string path) {
    std::ifstream fileRef(path);
    fileRef.open(path);
    if (file.is_open()) {
        name = path;
        return true;
    }
    return false;
}