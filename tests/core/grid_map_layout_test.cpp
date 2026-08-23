#include "province/core/grid_map_layout.hpp"

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {

using Json = nlohmann::json;

bool rejected(const Json& document, const std::string& suffix) {
    const auto path = std::filesystem::temp_directory_path() /
        ("province-grid-layout-" + suffix + ".json");
    {
        std::ofstream stream{path};
        stream << document.dump(2);
    }
    try {
        [[maybe_unused]] const auto layout =
            province::core::GridMapLayoutLoader::load(path);
    } catch (const province::core::DataLoadError&) {
        std::filesystem::remove(path);
        return true;
    }
    std::filesystem::remove(path);
    return false;
}

} // namespace

bool run_grid_map_layout_tests() {
    using province::core::CountryId;
    using province::core::GridCoordinate;
    using province::core::GridMapLayoutLoader;

    const auto source_path = std::filesystem::path{"game/data/grid_map_layout.json"};
    const auto layout = GridMapLayoutLoader::load(source_path);
    if (layout.layout_id != "generated_grid_v1" || layout.width != 9 ||
        layout.height != 9 || layout.cell_size != 80 || layout.countries.size() != 4) {
        std::cerr << "Grid layout header was parsed incorrectly\n";
        return false;
    }
    const auto& auroria = layout.countries.at(0);
    if (auroria.country_id != CountryId{"auroria"} ||
        auroria.minimum != GridCoordinate{1, 1} ||
        auroria.maximum != GridCoordinate{4, 4} ||
        auroria.capital_cells.size() != 4) {
        std::cerr << "Auroria grid placement was parsed incorrectly\n";
        return false;
    }

    std::ifstream stream{source_path};
    const Json valid = Json::parse(stream);

    Json duplicate = valid;
    duplicate["countries"][1]["id"] = "auroria";
    Json out_of_range = valid;
    out_of_range["countries"][0]["minimum"] = Json::array({0, 1});
    Json overlap = valid;
    overlap["countries"][1]["minimum"] = Json::array({4, 1});
    Json malformed_capital = valid;
    malformed_capital["countries"][0]["capital_cells"][3] = Json::array({4, 4});
    Json crosses_neutral = valid;
    crosses_neutral["countries"][0]["maximum"] = Json::array({5, 4});
    Json wrong_dimensions = valid;
    wrong_dimensions["width"] = 10;

    if (!rejected(duplicate, "duplicate") ||
        !rejected(out_of_range, "range") ||
        !rejected(overlap, "overlap") ||
        !rejected(malformed_capital, "capital") ||
        !rejected(crosses_neutral, "cross") ||
        !rejected(wrong_dimensions, "dimensions")) {
        std::cerr << "Invalid grid layout was accepted\n";
        return false;
    }
    return true;
}
