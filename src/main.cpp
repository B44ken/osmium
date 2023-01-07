#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <iostream>
#include <fstream>
#include <string>

#include "h/window.h"
#include "h/tab.h"
#include "h/text.h"

int main(int argc, char** argv) {

    std::string longLine = "According to folklore, the distinguishing feature of a hoop snake is that it can grasp its tail in its jaws and roll after its prey like a wheel; which is similar to the ouroboros in Greek mythology or the tsuchinoko in Japan. In one version of the myth, the snake straightens out at the last second, skewering its victim with its venomous tail. The only escape is to hide behind a tree, which receives the deadly blow instead and promptly dies from the poison.";
    Window mainWindow("Hoop Snake", 800, 600);

    mainWindow.setBackground({ 255, 0, 255 });
    mainWindow.drawText("According to folklore...");

    SDL_RWops* log = SDL_RWFromFile("log.txt", "w+");
    SDL_RWwrite(log, &longLine.c_str(), sizeof(longLine), 1);
    SDL_RWclose(log);

    SDL_Delay(1000);
    mainWindow.destroy();
    SDL_Quit();
    return 0;
}