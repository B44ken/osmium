#pragma once

#include <string>

#include "json.hpp"

class Config {
    public:
    Config();
    void read(std::string defaultsPath, std::string userConfigPath);
    nlohmann::json config;
};