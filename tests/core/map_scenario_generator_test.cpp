#include "province/core/map_scenario_generator.hpp"

#include "province/core/country.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/grid_map_layout.hpp"

#include <cstdint>
#include <iostream>
#include <map>
#include <set>

bool run_map_scenario_generator_tests() {
    using province::core::Country;
    using province::core::CountryId;
    using province::core::GameClock;
    using province::core::GameState;
    using province::core::GridMapLayoutLoader;
    using province::core::MapScenarioGenerator;
    using province::core::ProvinceId;
    using province::core::TerrainType;

    GameState initial{GameClock{1000, 1}};
    initial.add_country(Country{CountryId{"auroria"}, "Auroria", 0xC94B4B, 10'000, "A"});
    initial.add_country(Country{CountryId{"caelus"}, "Caelus", 0x4A79C9, 10'000, "C"});
    initial.add_country(Country{CountryId{"solmere"}, "Solmere", 0xD3A943, 10'000, "S"});
    initial.add_country(Country{CountryId{"verdantia"}, "Verdantia", 0x4FA66B, 10'000, "V"});
    const auto layout = GridMapLayoutLoader::load("game/data/grid_map_layout.json");
    const auto zero_random = [](const std::uint32_t) { return std::uint32_t{0}; };
    const GameState state = MapScenarioGenerator::generate(
        std::move(initial), layout, zero_random
    );

    const Country* neutral = state.find_country(CountryId{"neutral"});
    if (state.map_layout_id() != "generated_grid_v1" || state.country_count() != 5 ||
        state.province_count() != 69 || state.army_count() != 17 || neutral == nullptr ||
        !neutral->hidden || neutral->treasury != 0) {
        std::cerr << "Generated scenario counts or neutral country are incorrect\n";
        return false;
    }

    std::map<CountryId, std::size_t> owners;
    for (const auto& [province_id, province] : state.provinces()) {
        static_cast<void>(province_id);
        ++owners[province.owner_id];
        if (province.neighbors.empty()) {
            std::cerr << "Generated province has no neighbors\n";
            return false;
        }
        for (const ProvinceId& neighbor : province.neighbors) {
            if (!state.are_adjacent(province.id, neighbor)) {
                std::cerr << "Generated adjacency is not symmetric\n";
                return false;
            }
        }
    }
    if (owners[CountryId{"auroria"}] != 13 || owners[CountryId{"caelus"}] != 13 ||
        owners[CountryId{"solmere"}] != 13 || owners[CountryId{"verdantia"}] != 13 ||
        owners[CountryId{"neutral"}] != 17) {
        std::cerr << "Generated initial ownership counts are incorrect\n";
        return false;
    }

    const auto* capital = state.find_province(ProvinceId{"capital_auroria"});
    if (capital == nullptr || capital->name.empty() ||
        capital->terrain != TerrainType::capital || capital->population != 360'000 ||
        capital->recruitable_population != 3'600 || capital->base_economy != 360'000 ||
        capital->neighbors.size() != 8 ||
        state.find_province(ProvinceId{"cell_2_2"}) != nullptr) {
        std::cerr << "Auroria capital was not merged correctly\n";
        return false;
    }
    const auto* city = state.find_province(ProvinceId{"cell_1_1"});
    const auto* unowned = state.find_province(ProvinceId{"cell_5_5"});
    if (city == nullptr || city->name.empty() ||
        unowned == nullptr || unowned->name.empty() ||
        unowned->owner_id != CountryId{"neutral"} ||
        unowned->recruitable_population != 0) {
        std::cerr << "Generated province IDs or names are incorrect\n";
        return false;
    }

    std::map<ProvinceId, std::size_t> neutral_armies;
    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id != CountryId{"neutral"} || army.manpower != 900) {
            std::cerr << "Initial neutral guard is incorrect\n";
            return false;
        }
        ++neutral_armies[army.province_id];
    }
    for (const auto& [province_id, province] : state.provinces()) {
        if (province.owner_id == CountryId{"neutral"} && neutral_armies[province_id] != 1) {
            std::cerr << "Neutral province does not have exactly one guard\n";
            return false;
        }
    }
    for (const auto& [country_id, technology] : state.technologies()) {
        static_cast<void>(country_id);
        if (technology.economy_level != 0 || technology.military_level != 0 ||
            technology.roads_level != 0) {
            std::cerr << "Generated technologies did not start at zero\n";
            return false;
        }
    }
    if (!state.validate().empty()) {
        std::cerr << "Generated scenario failed state validation\n";
        return false;
    }
    return true;
}
