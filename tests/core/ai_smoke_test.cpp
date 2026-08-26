#include "smoke_test_groups.hpp"

#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/scenario_loader.hpp"

#include <cstdint>
#include <iostream>
#include <variant>
#include <vector>

bool run_ai_smoke_tests() {
    using namespace province::core;

    GameState state = ScenarioLoader::load(
        "game/data",
        GameClock{1000, 1},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    CommandProcessor processor;
    processor.enable_ai(CountryId{"auroria"});
    const CommandResult result = processor.execute(state, AdvanceTurnCommand{1});
    if (!result.accepted) {
        std::cerr << "AI-enabled generated turn was rejected\n";
        return false;
    }
    std::size_t human_armies = 0;
    std::size_t neutral_armies = 0;
    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id == CountryId{"auroria"}) ++human_armies;
        if (army.owner_id == CountryId{"neutral"}) ++neutral_armies;
    }
    if (human_armies != 0 || neutral_armies != 17) {
        std::cerr << "AI controlled the human or altered neutral guards\n";
        return false;
    }

    GameState delayed{GameClock{1000, 1}};
    const CountryId human{"human"};
    const CountryId ai{"ai"};
    const ProvinceId human_land{"human_land"};
    const ProvinceId ai_land{"ai_land"};
    delayed.add_country(Country{human, "Human", 0, 0, "HUM", false});
    delayed.add_country(Country{ai, "AI", 0, 0, "AIC", false});
    delayed.add_province(Province{
        human_land, "Human Land", human, 10'000, 1'000, 0,
        {ai_land}, 0, TerrainType::plains,
    });
    delayed.add_province(Province{
        ai_land, "AI Land", ai, 10'000, 1'000, 0,
        {human_land}, 0, TerrainType::plains,
    });
    delayed.set_diplomatic_status(ai, human, DiplomaticStatus::war);
    const ArmyId ai_army = delayed.create_army(ai, ai_land, 2'000);
    delayed.find_army(ai_army)->movement_points = 6;
    const std::vector<AiDecision> unaffordable = AiSystem{}.plan_month(delayed, human);
    for (const AiDecision& decision : unaffordable) {
        if (std::holds_alternative<MoveArmyCommand>(decision.command)) {
            std::cerr << "AI planned an attack without its movement surcharge\n";
            return false;
        }
    }

    delayed.find_army(ai_army)->movement_points = 12;
    CommandProcessor delayed_processor;
    delayed_processor.enable_ai(human);
    const CommandResult delayed_turn = delayed_processor.execute(
        delayed, AdvanceTurnCommand{1}
    );
    const Army* planned_army = delayed.find_army(ai_army);
    if (!delayed_turn.accepted || planned_army == nullptr ||
        planned_army->province_id != ai_land || delayed.orders().size() != 1) {
        std::cerr << "AI movement did not remain queued until a later month\n";
        return false;
    }
    const auto* planned_attack =
        std::get_if<ArmyActionOrder>(&delayed.orders().begin()->second);
    if (planned_attack == nullptr || !planned_attack->is_attack ||
        planned_attack->destination != human_land) {
        std::cerr << "AI did not create the expected delayed attack order\n";
        return false;
    }
    return true;
}
