#pragma once

#include "province/core/game_state.hpp"
#include "province/core/grid_map_layout.hpp"
#include "province/core/map_cell_generator.hpp"

namespace province::core {

class MapScenarioGenerator final {
public:
    [[nodiscard]] static GameState generate(
        GameState state,
        const GridMapLayout& layout,
        const RandomIndexSource& random_index
    );
};

} // namespace province::core
