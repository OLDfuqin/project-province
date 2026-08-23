#include "smoke_test_groups.hpp"

#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"
#include "province/core/save_game.hpp"

#include <filesystem>
#include <iostream>

bool run_save_game_smoke_tests() {
    using namespace province::core;

    GameState state{GameClock{1200, 6}};
    state.add_country(Country{CountryId{"alpha"}, "Alpha", 0xAA0000, 5'000, "A"});
    state.add_country(Country{CountryId{"beta"}, "Beta", 0x0000AA, 5'000, "B"});
    state.add_province(Province{
        ProvinceId{"alpha_home"}, "Alpha Home", CountryId{"alpha"},
        100'000, 1'000, 100'000, {ProvinceId{"beta_home"}}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        ProvinceId{"beta_home"}, "Beta Home", CountryId{"beta"},
        80'000, 800, 72'000, {ProvinceId{"alpha_home"}}, 0, TerrainType::hills,
    });
    const ArmyId army_id = state.create_army(
        CountryId{"alpha"}, ProvinceId{"alpha_home"}, 500
    );
    state.find_army(army_id)->movement_points = 5;
    state.find_army(army_id)->formation_number = 4;
    state.set_road_level(
        ProvinceId{"alpha_home"}, ProvinceId{"beta_home"}, RoadLevel::paved
    );
    state.set_diplomatic_status(
        CountryId{"alpha"}, CountryId{"beta"}, DiplomaticStatus::war
    );

    const auto path = std::filesystem::temp_directory_path() /
        "province-schema5-smoke.json";
    SaveGameSerializer::save(path, state, 7, CountryId{"alpha"});
    const LoadedGame loaded = SaveGameSerializer::load(path);
    std::filesystem::remove(path);

    const Army* loaded_army = loaded.state.find_army(army_id);
    const Province* loaded_hills = loaded.state.find_province(ProvinceId{"beta_home"});
    if (loaded.next_event_sequence != 7 || !loaded.human_country_id.has_value() ||
        *loaded.human_country_id != CountryId{"alpha"} || loaded_army == nullptr ||
        loaded_army->movement_points != 5 || loaded_army->formation_number != 4 ||
        loaded_hills == nullptr || loaded_hills->base_economy != 72'000 ||
        loaded.state.road_level(ProvinceId{"alpha_home"}, ProvinceId{"beta_home"}) !=
            RoadLevel::paved ||
        !loaded.state.are_at_war(CountryId{"alpha"}, CountryId{"beta"})) {
        std::cerr << "Schema 5 save round trip failed\n";
        return false;
    }
    return true;
}
