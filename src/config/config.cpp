#include <iostream>
#include <fstream>

#include "json.hpp"

class Config {
    public:
    Config();
    void read(std::string defaultsPath, std::string userConfigPath);
    nlohmann::json config;
};

Config::Config() {
    read("/mnt/c/dev/osmium/build/default.json", "/mnt/c/dev/osmium/build/user.json");
}

void Config::read(std::string defaultsPath, std::string userConfigPath) {
    std::ifstream defaultsFile(defaultsPath);
    if (!defaultsFile) {
        std::cout << "Error: defaults file not found" << std::endl;
        exit(1);
    }
    defaultsFile >> config;
    defaultsFile.close();

    std::ifstream userConfigFile(userConfigPath);
    if (!userConfigFile) {
        std::cout << "Warning: user config file not found" << std::endl;
    }

    nlohmann::json userConfig;
    userConfigFile >> userConfig;
    userConfigFile.close();

    config.merge_patch(userConfig);
}