#include <string>
#include <vector>

#include "../tab/tab.h"
#include "../editor/editor.h"

class TabList {
    public:
    TabList();
    void addEditorTab(std::string file);
    void addTerminalTab(std::string root);
    void closeTab();
    std::vector<Editor*> list;
    Editor* currentTab;
};

TabList::TabList() {
    addEditorTab("hoopsnake.txt");
}

void TabList::addEditorTab(std::string file) {
    Editor* editor = new Editor();
    editor->loadFile(file);
    list.push_back(editor);
    currentTab = editor;
}
