#include <iostream>
#include <string>
#include <vector>

#include "editor.h"

std::vector<std::string> getWords(std::string sentence, char split) {
    std::vector<std::string> words;
    std::string word;
    for(char c : sentence) {
        if(c == split) {
            words.push_back(word);
            word = "";
        } else {
            word += c;
        }
    }
    words.push_back(word);
    return words;
}

std::string wordWrapLine(std::string line, int maxLength) {
    std::vector<std::string> words = getWords(line, ' ');
    std::string output;
    std::string currentLine;
    for(std::string word : words) {
        if((int)currentLine.size() + (int)word.size() > maxLength) {
            output += currentLine + '\n';
            currentLine = word + ' ';
        } else {
            currentLine += word + ' ';
        }
    }
    output += currentLine + '\n';
    return output;
}

std::string wordWrap(std::vector<std::string> lines, int maxLength) {
    std::string output;
    for(std::string line : lines) {
        output += wordWrapLine(line, maxLength);
    }
    return output;
}



std::string Editor::outputFormatted() {
    return wordWrap(lines, lineLength);
}