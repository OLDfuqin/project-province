#include "smoke_test_groups.hpp"

#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/road.hpp"
#include "province/core/save_game.hpp"
#include "province/core/scenario_loader.hpp"

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <iostream>

bool run_save_game_smoke_tests() {
    using province::core::AdvanceTurnCommand;
    using province::core::ArmyId;
    using province::core::ArmyRecruitedEvent;
    using province::core::BuildRoadCommand;
    using province::core::CommandProcessor;
    using province::core::CommandResult;
    using province::core::CountryId;
    using province::core::DeclareWarCommand;
    using province::core::GameClock;
    using province::core::GameState;
    using province::core::MoveArmyCommand;
    using province::core::ProvinceId;
    using province::core::RecruitArmyCommand;
    using province::core::RenameArmyCommand;
    using province::core::ResearchTechnologyCommand;
    using province::core::RoadLevel;
    using province::core::ScenarioLoader;
    using province::core::TechnologyTrack;

    const std::filesystem::path save_path = "build/save_game_roundtrip_test.json";
    GameState state = ScenarioLoader::load("game/data", GameClock{1200, 6});
    CommandProcessor processor;
    [[maybe_unused]] const CommandResult technology = processor.execute(
        state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::roads}
    );
    const CommandResult recruitment = processor.execute(
        state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 500}
    );
    const ArmyId saved_army_id =
        std::get<ArmyRecruitedEvent>(recruitment.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult renamed = processor.execute(
        state,
        RenameArmyCommand{saved_army_id, 5}
    );
    [[maybe_unused]] const CommandResult road = processor.execute(
        state,
        BuildRoadCommand{
            CountryId{"auroria"}, ProvinceId{"northreach"}, ProvinceId{"westmark"}
        }
    );
    [[maybe_unused]] const CommandResult war = processor.execute(
        state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    [[maybe_unused]] const CommandResult month = processor.execute(
        state,
        AdvanceTurnCommand{1}
    );
    [[maybe_unused]] const CommandResult occupation = processor.execute(
        state,
        MoveArmyCommand{saved_army_id, ProvinceId{"redpass"}}
    );
    processor.enable_ai(CountryId{"auroria"});
    province::core::SaveGameSerializer::save(
        save_path,
        state,
        processor.next_event_sequence(),
        processor.human_country_id()
    );
    {
        std::ifstream saved_stream{save_path};
        const nlohmann::json saved_document = nlohmann::json::parse(saved_stream);
        bool saved_fixed_economy = false;
        for (const auto& province_document : saved_document.at("provinces")) {
            saved_fixed_economy = saved_fixed_economy ||
                province_document.contains("economy");
        }
        const auto& saved_country = saved_document.at("countries").front();
        const auto& saved_army = saved_document.at("armies").front();
        if (saved_document.at("schema_version").get<std::int32_t>() != 5 ||
            saved_fixed_economy || !saved_country.contains("code") ||
            !saved_army.contains("formation_number") ||
            !saved_army.contains("movement_points_half") ||
            saved_army.at("formation_number").get<std::int64_t>() != 5) {
            std::cerr << "Save game did not write formation identity schema\n";
            return false;
        }
    }
    province::core::LoadedGame loaded = province::core::SaveGameSerializer::load(save_path);
    if (loaded.state.clock().year() != state.clock().year() ||
        loaded.state.clock().month() != state.clock().month() ||
        loaded.state.army_count() != state.army_count() ||
        loaded.state.road_level(ProvinceId{"northreach"}, ProvinceId{"westmark"}) !=
            RoadLevel::paved ||
        !loaded.state.are_at_war(CountryId{"auroria"}, CountryId{"solmere"}) ||
        loaded.state.controller_of(ProvinceId{"redpass"}) != CountryId{"auroria"} ||
        loaded.state.find_technology(CountryId{"auroria"})->roads_level != 1 ||
        loaded.state.find_army(saved_army_id) == nullptr ||
        loaded.state.find_army(saved_army_id)->movement_points !=
            state.find_army(saved_army_id)->movement_points ||
        loaded.state.find_army(saved_army_id)->formation_number != 5 ||
        loaded.state.find_country(CountryId{"auroria"})->code !=
            state.find_country(CountryId{"auroria"})->code ||
        loaded.next_event_sequence != processor.next_event_sequence() ||
        !loaded.human_country_id.has_value() ||
        *loaded.human_country_id != CountryId{"auroria"}) {
        std::cerr << "Save game round trip did not preserve simulation state\n";
        return false;
    }

    const std::filesystem::path legacy_path = "build/save_game_schema3_test.json";
    {
        std::ifstream saved_stream{save_path};
        nlohmann::json legacy_document = nlohmann::json::parse(saved_stream);
        legacy_document["schema_version"] = 3;
        for (auto& country_document : legacy_document.at("countries")) {
            country_document.erase("code");
        }
        for (auto& army_document : legacy_document.at("armies")) {
            army_document.erase("formation_number");
            army_document["movement_points"] =
                army_document.at("movement_points_half").get<std::int32_t>() / 2;
            army_document.erase("movement_points_half");
        }
        std::ofstream legacy_stream{legacy_path};
        legacy_stream << legacy_document.dump(2) << '\n';
    }
    const province::core::LoadedGame legacy_loaded =
        province::core::SaveGameSerializer::load(legacy_path);
    if (legacy_loaded.state.find_army(saved_army_id) == nullptr ||
        legacy_loaded.state.find_army(saved_army_id)->formation_number != 1 ||
        legacy_loaded.state.find_country(CountryId{"auroria"})->code.empty()) {
        std::cerr << "Schema 3 formation identity migration failed\n";
        return false;
    }
    CommandProcessor restored_processor;
    restored_processor.set_next_event_sequence(loaded.next_event_sequence);
    restored_processor.enable_ai(*loaded.human_country_id);
    const CommandResult post_load_recruitment = restored_processor.execute(
        loaded.state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"westmark"}, 100}
    );
    const auto& post_load_event =
        std::get<ArmyRecruitedEvent>(post_load_recruitment.events.front().payload);
    if (!post_load_recruitment.accepted || post_load_event.army_id != ArmyId{"army_2"} ||
        post_load_recruitment.events.front().sequence != processor.next_event_sequence()) {
        std::cerr << "Save game did not preserve entity and event sequences\n";
        return false;
    }
    std::filesystem::remove(save_path);
    std::filesystem::remove(legacy_path);
    return true;
}
