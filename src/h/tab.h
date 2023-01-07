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