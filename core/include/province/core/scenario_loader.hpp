#pragma once

#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"

#include <filesystem>
#include <stdexcept>
#include <string>

namespace province::core {

class DataLoadError final : public std::runtime_error {
public:
    explicit DataLoadError(const std::string& message);
};

class ScenarioLoader final {
public:
    [[nodiscard]] static GameState load(
        const std::filesystem::path& data_directory,
        GameClock initial_clock
    );
};

} // namespace province::core

