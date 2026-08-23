#include "province/core/map_scenario_generator.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>

namespace province::core {
namespace {

const CountryId neutral_id{"neutral"};
constexpr const char* capital_suffix = "\xE9\xA6\x96\xE9\x83\xBD";
constexpr const char* city_suffix = "\xE5\x9F\x8E\xE5\xB8\x82";
constexpr const char* unowned_prefix = "\xE6\x97\xA0\xE4\xB8\xBB\xE5\x9C\xB0\xE5\x9D\x97";

std::string cell_id(const GridCoordinate coordinate) {
    return "cell_" + std::to_string(coordinate.x) + "_" + std::to_string(coordinate.y);
}

std::string coordinate_suffix(const GridCoordinate coordinate) {
    return "(" + std::to_string(coordinate.x) + "," + std::to_string(coordinate.y) + ")";
}

void checked_add(std::int64_t& target, const std::int64_t value) {
    if (value < 0 || target > std::numeric_limits<std::int64_t>::max() - value) {
        throw std::overflow_error{"capital aggregate overflow"};
    }
    target += value;
}

} // namespace

GameState MapScenarioGenerator::generate(
    GameState state,
    const GridMapLayout& layout,
    const RandomIndexSource& random_index
) {
    if (state.country_count() != 4 || state.province_count() != 0 ||
        state.army_count() != 0 || state.find_country(neutral_id) != nullptr) {
        throw std::invalid_argument{"map scenario generator requires four empty normal countries"};
    }
    for (const CountryGridPlacement& placement : layout.countries) {
        const Country* country = state.find_country(placement.country_id);
        if (country == nullptr || country->hidden) {
            throw std::invalid_argument{"grid placement references a missing normal country"};
        }
    }
    state.add_country(Country{neutral_id, "Neutral Guard", 0x596579, 0, "N", true});
    state.map_layout_id_ = layout.layout_id;

    const auto cells = MapCellGenerator::generate(layout, random_index);
    std::map<GridCoordinate, CountryId> owner_by_coordinate;
    std::map<GridCoordinate, ProvinceId> province_by_coordinate;
    for (std::int32_t y = 1; y <= layout.height; ++y) {
        for (std::int32_t x = 1; x <= layout.width; ++x) {
            const GridCoordinate coordinate{x, y};
            const CountryGridPlacement* owner_placement = nullptr;
            bool capital_cell = false;
            for (const CountryGridPlacement& placement : layout.countries) {
                if (x < placement.minimum.x || x > placement.maximum.x ||
                    y < placement.minimum.y || y > placement.maximum.y) continue;
                owner_placement = &placement;
                capital_cell = std::find(
                    placement.capital_cells.begin(), placement.capital_cells.end(), coordinate
                ) != placement.capital_cells.end();
                break;
            }
            const CountryId owner = owner_placement == nullptr ? neutral_id :
                owner_placement->country_id;
            owner_by_coordinate.emplace(coordinate, owner);
            province_by_coordinate.emplace(
                coordinate,
                ProvinceId{capital_cell ? "capital_" + owner.value() : cell_id(coordinate)}
            );
        }
    }

    std::map<ProvinceId, Province> provinces;
    for (const GeneratedMapCell& cell : cells) {
        const CountryId& owner = owner_by_coordinate.at(cell.coordinate);
        const ProvinceId& province_id = province_by_coordinate.at(cell.coordinate);
        auto existing = provinces.find(province_id);
        if (existing == provinces.end()) {
            const Country* country = state.find_country(owner);
            if (country == nullptr) throw std::logic_error{"generated owner disappeared"};
            const bool capital = province_id.value().starts_with("capital_");
            const bool neutral = owner == neutral_id;
            const std::string name = capital
                ? country->name + capital_suffix
                : neutral
                    ? std::string{unowned_prefix} + coordinate_suffix(cell.coordinate)
                    : country->name + city_suffix + coordinate_suffix(cell.coordinate);
            provinces.emplace(province_id, Province{
                province_id,
                name,
                owner,
                cell.population,
                neutral ? 0 : cell.population / 100,
                cell.base_economy,
                {},
                0,
                capital ? TerrainType::capital : cell.terrain,
            });
        } else {
            checked_add(existing->second.population, cell.population);
            checked_add(existing->second.recruitable_population, cell.population / 100);
            checked_add(existing->second.base_economy, cell.base_economy);
        }
    }

    std::map<ProvinceId, std::set<ProvinceId>> adjacency;
    for (const auto& [province_id, province] : provinces) {
        static_cast<void>(province);
        adjacency.emplace(province_id, std::set<ProvinceId>{});
    }
    constexpr std::array<GridCoordinate, 2> offsets{
        GridCoordinate{1, 0}, GridCoordinate{0, 1}
    };
    for (std::int32_t y = 1; y <= layout.height; ++y) {
        for (std::int32_t x = 1; x <= layout.width; ++x) {
            const GridCoordinate coordinate{x, y};
            const ProvinceId& source = province_by_coordinate.at(coordinate);
            for (const GridCoordinate offset : offsets) {
                const auto neighbor = province_by_coordinate.find(
                    {x + offset.x, y + offset.y}
                );
                if (neighbor == province_by_coordinate.end() || source == neighbor->second) {
                    continue;
                }
                adjacency.at(source).insert(neighbor->second);
                adjacency.at(neighbor->second).insert(source);
            }
        }
    }
    for (auto& [province_id, province] : provinces) {
        const auto& neighbors = adjacency.at(province_id);
        province.neighbors.assign(neighbors.begin(), neighbors.end());
        state.add_province(std::move(province));
    }

    std::size_t neutral_provinces = 0;
    for (const auto& [province_id, province] : state.provinces()) {
        if (province.owner_id != neutral_id) continue;
        ++neutral_provinces;
        [[maybe_unused]] const ArmyId guard = state.create_army(
            neutral_id, province_id, province.population / 100
        );
    }
    if (state.province_count() != 69 || neutral_provinces != 17 ||
        state.army_count() != 17) {
        throw std::logic_error{"generated map scenario has incorrect entity counts"};
    }
    if (!state.validate().empty()) {
        throw std::logic_error{"generated map scenario failed validation"};
    }
    return state;
}

} // namespace province::core
