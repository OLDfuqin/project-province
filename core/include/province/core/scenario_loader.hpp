#pragma once

#include "province/core/data_load_error.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"
#include "province/core/map_cell_generator.hpp"

#include <filesystem>
#include <stdexcept>
#include <string>

namespace province::core {

class ScenarioLoader final {
public:
    [[nodiscard]] static GameState load(
        const std::filesystem::path& data_directory,
        GameClock initial_clock,
        RandomIndexSource random_index = {}
    );
};

} // namespace province::core
