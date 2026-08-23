#include "province/core/grid_map_layout.hpp"

#include <nlohmann/json.hpp>

#include <fstream>
#include <map>
#include <set>
#include <stdexcept>
#include <utility>

namespace province::core {
namespace {

using Json = nlohmann::json;

GridCoordinate coordinate_from_json(const Json& value) {
    if (!value.is_array() || value.size() != 2) {
        throw std::invalid_argument{"grid coordinate must contain exactly two integers"};
    }
    return {value.at(0).get<std::int32_t>(), value.at(1).get<std::int32_t>()};
}

bool contains(
    const CountryGridPlacement& placement,
    const GridCoordinate coordinate
) noexcept {
    return coordinate.x >= placement.minimum.x &&
        coordinate.x <= placement.maximum.x &&
        coordinate.y >= placement.minimum.y &&
        coordinate.y <= placement.maximum.y;
}

void validate_layout(const GridMapLayout& layout) {
    if (layout.layout_id != "generated_grid_v1" || layout.width != 9 ||
        layout.height != 9 || layout.cell_size <= 0 || layout.countries.size() != 4) {
        throw std::invalid_argument{"generated grid layout header is invalid"};
    }

    const std::map<CountryId, std::pair<GridCoordinate, GridCoordinate>> expected{
        {CountryId{"auroria"}, {{1, 1}, {4, 4}}},
        {CountryId{"caelus"}, {{6, 1}, {9, 4}}},
        {CountryId{"solmere"}, {{1, 6}, {4, 9}}},
        {CountryId{"verdantia"}, {{6, 6}, {9, 9}}},
    };
    std::set<CountryId> country_ids;
    std::set<GridCoordinate> owned_cells;
    for (const CountryGridPlacement& placement : layout.countries) {
        if (!country_ids.insert(placement.country_id).second) {
            throw std::invalid_argument{"grid layout contains duplicate country ID"};
        }
        const auto expected_placement = expected.find(placement.country_id);
        if (expected_placement == expected.end() ||
            placement.minimum != expected_placement->second.first ||
            placement.maximum != expected_placement->second.second) {
            throw std::invalid_argument{"country is not in its required corner"};
        }
        if (placement.capital_cells.size() != 4) {
            throw std::invalid_argument{"capital must contain four cells"};
        }
        const std::set<GridCoordinate> expected_capital{
            {placement.minimum.x + 1, placement.minimum.y + 1},
            {placement.minimum.x + 2, placement.minimum.y + 1},
            {placement.minimum.x + 1, placement.minimum.y + 2},
            {placement.minimum.x + 2, placement.minimum.y + 2},
        };
        const std::set<GridCoordinate> actual_capital{
            placement.capital_cells.begin(), placement.capital_cells.end()
        };
        if (actual_capital != expected_capital) {
            throw std::invalid_argument{"capital cells are not the central 2x2 square"};
        }
        for (std::int32_t y = placement.minimum.y; y <= placement.maximum.y; ++y) {
            for (std::int32_t x = placement.minimum.x; x <= placement.maximum.x; ++x) {
                const GridCoordinate coordinate{x, y};
                if (x < 1 || x > layout.width || y < 1 || y > layout.height ||
                    x == 5 || y == 5 || !contains(placement, coordinate) ||
                    !owned_cells.insert(coordinate).second) {
                    throw std::invalid_argument{"country grid cells overlap or enter neutral cross"};
                }
            }
        }
    }
    if (owned_cells.size() != 64 ||
        static_cast<std::size_t>(layout.width * layout.height) - owned_cells.size() != 17) {
        throw std::invalid_argument{"grid layout must leave exactly 17 neutral cells"};
    }
}

} // namespace

GridMapLayout GridMapLayoutLoader::load(const std::filesystem::path& path) {
    std::ifstream stream{path};
    if (!stream) {
        throw DataLoadError{"cannot open grid layout file: " + path.string()};
    }
    try {
        const Json document = Json::parse(stream);
        if (document.at("schema_version").get<std::int32_t>() != 1) {
            throw std::invalid_argument{"grid layout schema version must be 1"};
        }
        GridMapLayout layout{
            document.at("layout_id").get<std::string>(),
            document.at("width").get<std::int32_t>(),
            document.at("height").get<std::int32_t>(),
            document.at("cell_size").get<std::int32_t>(),
            {},
        };
        for (const Json& entry : document.at("countries")) {
            CountryGridPlacement placement{
                CountryId{entry.at("id").get<std::string>()},
                coordinate_from_json(entry.at("minimum")),
                coordinate_from_json(entry.at("maximum")),
                {},
            };
            for (const Json& cell : entry.at("capital_cells")) {
                placement.capital_cells.push_back(coordinate_from_json(cell));
            }
            layout.countries.push_back(std::move(placement));
        }
        validate_layout(layout);
        return layout;
    } catch (const DataLoadError&) {
        throw;
    } catch (const std::exception& error) {
        throw DataLoadError{
            "invalid grid layout in '" + path.string() + "': " + error.what()
        };
    }
}

} // namespace province::core
