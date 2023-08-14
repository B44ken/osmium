#include <string>
#include <vector>

std::vector<std::string> getWords(std::string sentence, char split);

std::string wordWrap(std::vector<std::string> lines, long unsigned int maxLength);

std::string wordWrapLine(std::string line, int maxLength);