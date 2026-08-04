#include "smoke_test_groups.hpp"

#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/scenario_loader.hpp"

#include <iostream>

bool run_ai_smoke_tests() {
    using province::core::AdvanceTurnCommand;
    using province::core::ArmyId;
    using province::core::ArmyRecruitedEvent;
    using province::core::CommandProcessor;
    using province::core::CommandResult;
    using province::core::CountryId;
    using province::core::DeclareWarCommand;
    using province::core::GameClock;
    using province::core::GameState;
    using province::core::ProvinceId;
    using province::core::RecruitArmyCommand;
    using province::core::ScenarioLoader;

    GameState ai_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor ai_processor;
    ai_processor.enable_ai(CountryId{"auroria"});
    const CommandResult first_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult second_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult third_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult fourth_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    std::int64_t player_armies = 0;
    for (const auto& [army_id, army] : ai_state.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id == CountryId{"auroria"}) {
            ++player_armies;
        }
    }
    if (!first_ai_month.accepted || !second_ai_month.accepted ||
        !third_ai_month.accepted || !fourth_ai_month.accepted ||
        ai_state.army_count() != 9 || player_armies != 0 ||
        ai_state.relations().empty() || ai_state.occupations().empty() ||
        first_ai_month.events.size() != 7) {
        std::cerr << "AI did not recruit, declare war and advance deterministically\n";
        return false;
    }

    GameState path_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor path_processor;
    const CommandResult rear_army_result = path_processor.execute(
        path_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"goldcoast"}, 500}
    );
    const ArmyId rear_army_id =
        std::get<ArmyRecruitedEvent>(rear_army_result.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult war = path_processor.execute(
        path_state,
        DeclareWarCommand{CountryId{"solmere"}, CountryId{"auroria"}}
    );
    path_processor.enable_ai(CountryId{"auroria"});
    [[maybe_unused]] const CommandResult month = path_processor.execute(
        path_state,
        AdvanceTurnCommand{1}
    );
    if (path_state.find_army(rear_army_id)->province_id != ProvinceId{"redpass"}) {
        std::cerr << "AI pathfinding did not move a rear army toward the front\n";
        return false;
    }
    return true;
}
