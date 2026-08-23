#include "smoke_test_groups.hpp"

#include "province/core/save_game.hpp"
#include "province/core/scenario_loader.hpp"

#include <nlohmann/json.hpp>

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

namespace {

using Json = nlohmann::json;

bool rejected(const Json& document, const std::string& suffix) {
    const auto path = std::filesystem::temp_directory_path() /
        ("province-invalid-save-" + suffix + ".json");
    {
        std::ofstream stream{path};
        stream << document.dump(2);
    }
    try {
        [[maybe_unused]] const auto loaded = province::core::SaveGameSerializer::load(path);
    } catch (const province::core::SaveGameError&) {
        std::filesystem::remove(path);
        return true;
    }
    std::filesystem::remove(path);
    return false;
}

} // namespace

bool run_save_game_smoke_tests() {
    using namespace province::core;

    GameState state = ScenarioLoader::load(
        "game/data",
        GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema6-smoke.json";
    SaveGameSerializer::save(path, state, 7, CountryId{"auroria"});

    std::ifstream stream{path};
    const Json document = Json::parse(stream);
    stream.close();
    bool found_hidden = false;
    bool every_base = true;
    for (const Json& country : document.at("countries")) {
        if (country.at("id") == "neutral") {
            found_hidden = country.at("hidden").get<bool>();
        }
    }
    for (const Json& province : document.at("provinces")) {
        every_base = every_base && province.contains("base_economy");
    }
    if (document.at("schema_version") != 6 ||
        document.at("map_layout_id") != "generated_grid_v1" ||
        document.at("countries").size() != 5 || document.at("provinces").size() != 69 ||
        document.at("armies").size() != 17 || !found_hidden || !every_base) {
        std::cerr << "Schema 6 did not persist generated-map fields\n";
        std::filesystem::remove(path);
        return false;
    }

    LoadedGame loaded{GameState{GameClock{1, 1}}, 1, std::nullopt};
    try {
        loaded = SaveGameSerializer::load(path);
    } catch (const SaveGameError& error) {
        std::cerr << "Schema 6 load failed: " << error.what() << "\n";
        std::filesystem::remove(path);
        return false;
    }
    std::filesystem::remove(path);
    const Province* capital = loaded.state.find_province(ProvinceId{"capital_auroria"});
    if (loaded.next_event_sequence != 7 || !loaded.human_country_id.has_value() ||
        *loaded.human_country_id != CountryId{"auroria"} ||
        loaded.state.map_layout_id() != "generated_grid_v1" ||
        loaded.state.province_count() != 69 || loaded.state.army_count() != 17 ||
        loaded.state.find_country(CountryId{"neutral"}) == nullptr ||
        !loaded.state.find_country(CountryId{"neutral"})->hidden || capital == nullptr ||
        capital->terrain != TerrainType::capital || capital->base_economy != 360'000) {
        std::cerr << "Schema 6 generated map round trip failed\n";
        return false;
    }

    Json legacy = document;
    legacy["schema_version"] = 5;
    Json wrong_layout = document;
    wrong_layout["map_layout_id"] = "different_layout";
    if (!rejected(legacy, "legacy") || !rejected(wrong_layout, "layout")) {
        std::cerr << "Incompatible generated-map save was accepted\n";
        return false;
    }
    return true;
}
