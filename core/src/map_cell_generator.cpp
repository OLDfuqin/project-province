#include "province/core/map_cell_generator.hpp"

#include <array>
#include <map>
#include <stdexcept>
#include <vector>

namespace province::core {
namespace {

struct ReliefWeights final {
    std::uint32_t plains{};
    std::uint32_t hills{};
    std::uint32_t mountains{};
};

std::uint32_t draw(
    const RandomIndexSource& random_index,
    const std::uint32_t exclusive_upper_bound
) {
    const std::uint32_t value = random_index(exclusive_upper_bound);
    if (value >= exclusive_upper_bound) {
        throw std::out_of_range{"map random source returned an out-of-range index"};
    }
    return value;
}

ReliefWeights weights_for(const BaseRelief relief) noexcept {
    switch (relief) {
    case BaseRelief::plains: return {50, 50, 0};
    case BaseRelief::hills: return {40, 30, 30};
    case BaseRelief::mountains: return {0, 50, 50};
    }
    return {50, 50, 0};
}

BaseRelief choose_relief(
    const ReliefWeights weights,
    const RandomIndexSource& random_index
) {
    const std::uint32_t total = weights.plains + weights.hills + weights.mountains;
    const std::uint32_t value = draw(random_index, total);
    if (value < weights.plains) return BaseRelief::plains;
    if (value < weights.plains + weights.hills) return BaseRelief::hills;
    return BaseRelief::mountains;
}

std::array<std::int64_t, 4> population_values(const TerrainType terrain) {
    switch (terrain) {
    case TerrainType::mountains: return {30'000, 40'000, 50'000, 60'000};
    case TerrainType::hills: return {50'000, 60'000, 70'000, 80'000};
    case TerrainType::forest: return {70'000, 80'000, 90'000, 100'000};
    case TerrainType::plains:
    case TerrainType::capital: return {90'000, 100'000, 110'000, 120'000};
    }
    return {90'000, 100'000, 110'000, 120'000};
}

std::int64_t scaled_economy(
    const std::int64_t population,
    const TerrainType terrain
) noexcept {
    const std::int64_t percent = terrain_economy_percent(terrain);
    return (population / 100) * percent + (population % 100) * percent / 100;
}

} // namespace

std::vector<GeneratedMapCell> MapCellGenerator::generate(
    const GridMapLayout& layout,
    const RandomIndexSource& random_index
) {
    if (!random_index) {
        throw std::invalid_argument{"map cell generation requires a random source"};
    }
    std::vector<GeneratedMapCell> cells;
    cells.reserve(static_cast<std::size_t>(layout.width * layout.height));
    std::map<GridCoordinate, GeneratedMapCell> generated;
    constexpr std::array<GridCoordinate, 4> offsets{
        GridCoordinate{-1, 0}, GridCoordinate{1, 0},
        GridCoordinate{0, -1}, GridCoordinate{0, 1},
    };

    for (std::int32_t y = 1; y <= layout.height; ++y) {
        const bool left_to_right = (y % 2) == 1;
        for (std::int32_t step = 0; step < layout.width; ++step) {
            const std::int32_t x = left_to_right ? step + 1 : layout.width - step;
            const GridCoordinate coordinate{x, y};
            BaseRelief relief = BaseRelief::plains;
            if (coordinate != GridCoordinate{1, 1}) {
                ReliefWeights sum{};
                std::uint32_t count = 0;
                for (const GridCoordinate offset : offsets) {
                    const auto neighbor = generated.find({x + offset.x, y + offset.y});
                    if (neighbor == generated.end()) continue;
                    const ReliefWeights weights = weights_for(neighbor->second.base_relief);
                    sum.plains += weights.plains;
                    sum.hills += weights.hills;
                    sum.mountains += weights.mountains;
                    ++count;
                }
                if (count == 0 || count > 2) {
                    throw std::logic_error{"snake traversal produced an invalid parent count"};
                }
                relief = choose_relief(
                    {sum.plains / count, sum.hills / count, sum.mountains / count},
                    random_index
                );
            }

            TerrainType terrain = relief == BaseRelief::plains ? TerrainType::plains :
                relief == BaseRelief::hills ? TerrainType::hills : TerrainType::mountains;
            if (relief != BaseRelief::plains && draw(random_index, 2) == 1) {
                terrain = TerrainType::forest;
            }
            const auto values = population_values(terrain);
            const std::int64_t population = values.at(draw(random_index, 4));
            GeneratedMapCell cell{
                coordinate, relief, terrain, population, scaled_economy(population, terrain)
            };
            generated.emplace(coordinate, cell);
            cells.push_back(std::move(cell));
        }
    }
    return cells;
}

} // namespace province::core
