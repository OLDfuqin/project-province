#pragma once

#include "province/core/grid_map_layout.hpp"
#include "province/core/terrain.hpp"

#include <cstdint>
#include <functional>
#include <vector>

namespace province::core {

enum class BaseRelief : std::uint8_t { plains, hills, mountains };

struct GeneratedMapCell final {
    GridCoordinate coordinate;
    BaseRelief base_relief{BaseRelief::plains};
    TerrainType terrain{TerrainType::plains};
    std::int64_t population{};
    std::int64_t base_economy{};
};

using RandomIndexSource = std::function<std::uint32_t(std::uint32_t exclusive_upper_bound)>;

class MapCellGenerator final {
public:
    [[nodiscard]] static std::vector<GeneratedMapCell> generate(
        const GridMapLayout& layout,
        const RandomIndexSource& random_index
    );
};

} // namespace province::core
