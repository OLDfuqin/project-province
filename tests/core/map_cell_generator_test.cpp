#include "province/core/map_cell_generator.hpp"

#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

bool run_map_cell_generator_tests() {
    using province::core::BaseRelief;
    using province::core::GridCoordinate;
    using province::core::GridMapLayoutLoader;
    using province::core::MapCellGenerator;
    using province::core::TerrainType;

    const auto layout = GridMapLayoutLoader::load("game/data/grid_map_layout.json");
    std::vector<std::uint32_t> bounds;
    const auto zero_random = [&bounds](const std::uint32_t bound) {
        bounds.push_back(bound);
        return std::uint32_t{0};
    };
    const auto cells = MapCellGenerator::generate(layout, zero_random);
    if (cells.size() != 81 || cells.front().coordinate != GridCoordinate{1, 1} ||
        cells.at(8).coordinate != GridCoordinate{9, 1} ||
        cells.at(9).coordinate != GridCoordinate{9, 2} ||
        cells.at(17).coordinate != GridCoordinate{1, 2} ||
        cells.back().coordinate != GridCoordinate{9, 9}) {
        std::cerr << "Map cells were not generated in snake order\n";
        return false;
    }
    for (const auto& cell : cells) {
        if (cell.base_relief != BaseRelief::plains || cell.terrain != TerrainType::plains ||
            cell.population != 90'000 || cell.base_economy != 90'000) {
            std::cerr << "Zero random source did not select plains minimums\n";
            return false;
        }
    }
    if (bounds.size() != 161 || bounds.front() != 4) {
        std::cerr << "Unexpected random call count for all-plains generation\n";
        return false;
    }
    for (std::size_t index = 1; index < bounds.size(); index += 2) {
        if (bounds[index] != 100 || bounds[index + 1] != 4) {
            std::cerr << "Relief or population random bound is incorrect\n";
            return false;
        }
    }

    std::size_t relief_calls = 0;
    const auto forest_random = [&relief_calls](const std::uint32_t bound) {
        if (bound == 100) {
            ++relief_calls;
            return std::uint32_t{50};
        }
        if (bound == 2) return std::uint32_t{1};
        return std::uint32_t{0};
    };
    const auto forest_cells = MapCellGenerator::generate(layout, forest_random);
    if (relief_calls != 80 || forest_cells.at(1).base_relief != BaseRelief::hills ||
        forest_cells.at(1).terrain != TerrainType::forest ||
        forest_cells.at(1).population != 70'000 ||
        forest_cells.at(1).base_economy != 63'000 ||
        forest_cells.at(9).base_relief != BaseRelief::hills) {
        std::cerr << "Hills propagation or forest overlay is incorrect\n";
        return false;
    }

    bool rejected_missing = false;
    try {
        [[maybe_unused]] const auto invalid = MapCellGenerator::generate(layout, {});
    } catch (const std::invalid_argument&) {
        rejected_missing = true;
    }
    bool rejected_range = false;
    try {
        [[maybe_unused]] const auto invalid = MapCellGenerator::generate(
            layout,
            [](const std::uint32_t bound) { return bound; }
        );
    } catch (const std::out_of_range&) {
        rejected_range = true;
    }
    if (!rejected_missing || !rejected_range) {
        std::cerr << "Invalid random source was accepted\n";
        return false;
    }
    return true;
}
