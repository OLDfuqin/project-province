#include "smoke_test_groups.hpp"

#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/order_system.hpp"
#include "province/core/scenario_loader.hpp"

#include <cstdint>
#include <iostream>
#include <variant>
#include <vector>

namespace {

using namespace province::core;

bool has_move_decision(
    const std::vector<AiDecision>& decisions,
    const CountryId& country_id,
    const ProvinceId& destination
) {
    for (const AiDecision& decision : decisions) {
        const auto* move = std::get_if<MoveArmyCommand>(&decision.command);
        if (decision.country_id == country_id && move != nullptr &&
            move->destination == destination) {
            return true;
        }
    }
    return false;
}

bool test_generated_scenario_excludes_human_and_neutral() {

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

    return true;
}

bool test_ai_does_not_propose_unaffordable_recruitment() {
    GameState state{GameClock{1000, 1}};
    const CountryId human{"human"};
    const CountryId ai{"ai"};
    const ProvinceId ai_land{"ai_land"};
    state.add_country(Country{human, "Human", 0, 0, "HUM", false});
    state.add_country(Country{ai, "AI", 0, 500, "AIC", false});
    state.add_province(Province{
        ai_land, "AI Land", ai, 10'000, 1'000, 0,
        {}, 0, TerrainType::plains,
    });

    const std::vector<AiDecision> decisions = AiSystem{}.plan_month(state, human);
    for (const AiDecision& decision : decisions) {
        if (decision.country_id == ai &&
            std::holds_alternative<RecruitArmyCommand>(decision.command)) {
            std::cerr << "AI proposed recruitment without the fourfold recruitment cost\n";
            return false;
        }
    }
    state.find_country(ai)->treasury = -1;
    CommandProcessor processor;
    processor.enable_ai(state, human);
    if (!state.orders().empty()) {
        std::cerr << "AI queued a paid project while its country was in debt\n";
        return false;
    }
    return true;
}

bool test_ai_planning_respects_existing_attack_target_lock() {
    GameState state{GameClock{1000, 1}};
    const CountryId human{"human"};
    const CountryId ai{"ai"};
    const CountryId rival{"rival"};
    const CountryId defender{"defender"};
    const ProvinceId ai_land{"ai_land"};
    const ProvinceId rival_land{"rival_land"};
    const ProvinceId target{"target"};
    state.add_country(Country{human, "Human", 0, 0, "HUM", false});
    state.add_country(Country{ai, "AI", 0, 0, "AIC", false});
    state.add_country(Country{rival, "Rival", 0, 0, "RIV", false});
    state.add_country(Country{defender, "Defender", 0, 0, "DEF", false});
    state.add_province(Province{
        ai_land, "AI Land", ai, 10'000, 1'000, 0,
        {target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        rival_land, "Rival Land", rival, 10'000, 1'000, 0,
        {target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        target, "Target", defender, 10'000, 1'000, 0,
        {ai_land, rival_land}, 0, TerrainType::plains,
    });
    state.set_diplomatic_status(ai, defender, DiplomaticStatus::war);
    state.set_diplomatic_status(rival, defender, DiplomaticStatus::war);
    const ArmyId ai_army = state.create_army(ai, ai_land, 2'000);
    const ArmyId rival_army = state.create_army(rival, rival_land, 2'000);
    state.find_army(ai_army)->movement_points = 12;
    state.find_army(rival_army)->movement_points = 12;
    if (!OrderSystem{}.queue_army_action(
            state, rival_army, {rival_land, target}, true
        ).accepted) {
        return false;
    }

    const std::vector<AiDecision> decisions = AiSystem{}.plan_month(state, human);
    if (has_move_decision(decisions, ai, target)) {
        std::cerr << "AI proposed an attack against another country's locked target\n";
        return false;
    }
    return true;
}

bool test_ai_initial_orders_wait_and_execute_next_month() {

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

    CommandProcessor delayed_processor;
    delayed.find_army(ai_army)->movement_points = 12;
    delayed_processor.enable_ai(delayed, human);
    const Army* initially_planned_army = delayed.find_army(ai_army);
    if (initially_planned_army == nullptr ||
        initially_planned_army->province_id != ai_land || delayed.orders().size() != 1) {
        std::cerr << "Enabling AI did not create its first-month delayed order\n";
        return false;
    }
    const auto* initial_attack =
        std::get_if<ArmyActionOrder>(&delayed.orders().begin()->second);
    if (initial_attack == nullptr || !initial_attack->is_attack ||
        initial_attack->destination != human_land) {
        std::cerr << "Initial AI plan did not queue the expected attack\n";
        return false;
    }

    const CommandResult delayed_turn = delayed_processor.execute(
        delayed, AdvanceTurnCommand{1}
    );
    const Army* planned_army = delayed.find_army(ai_army);
    if (!delayed_turn.accepted || planned_army == nullptr ||
        planned_army->province_id != human_land ||
        delayed.controller_of(human_land) != ai) {
        std::cerr << "Initial AI order did not execute on the following month\n";
        return false;
    }
    return true;
}

bool test_post_settlement_ai_order_cannot_see_later_human_order() {
    GameState state{GameClock{1000, 1}};
    const CountryId human{"human"};
    const CountryId ai{"ai"};
    const CountryId defender{"defender"};
    const ProvinceId human_land{"human_land"};
    const ProvinceId ai_land{"ai_land"};
    const ProvinceId target{"target"};
    state.add_country(Country{human, "Human", 0, 0, "HUM", false});
    state.add_country(Country{ai, "AI", 0, 0, "AIC", false});
    state.add_country(Country{defender, "Defender", 0, 0, "DEF", false});
    state.add_province(Province{
        human_land, "Human Land", human, 10'000, 1'000, 0,
        {target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        ai_land, "AI Land", ai, 10'000, 1'000, 0,
        {target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        target, "Target", defender, 10'000, 1'000, 0,
        {human_land, ai_land}, 0, TerrainType::plains,
    });
    state.set_diplomatic_status(human, defender, DiplomaticStatus::war);
    state.set_diplomatic_status(ai, defender, DiplomaticStatus::war);
    const ArmyId human_army = state.create_army(human, human_land, 2'000);
    const ArmyId ai_army = state.create_army(ai, ai_land, 2'000);
    state.find_army(human_army)->movement_points = 12;
    state.find_army(ai_army)->movement_points = 12;

    CommandProcessor processor;
    processor.enable_ai(human);
    const CommandResult settled = processor.execute(state, AdvanceTurnCommand{1});
    if (!settled.accepted || state.orders().size() != 1 ||
        state.find_army(ai_army)->province_id != ai_land ||
        state.controller_of(target) != defender) {
        std::cerr << "AI action did not remain queued after its planning settlement\n";
        return false;
    }
    for (const GameEvent& event : settled.events) {
        if (event.type == GameEventType::order_created) {
            std::cerr << "Hidden AI order was exposed through the public turn events\n";
            return false;
        }
    }
    const auto* ai_order = std::get_if<ArmyActionOrder>(&state.orders().begin()->second);
    if (ai_order == nullptr || ai_order->army_id != ai_army ||
        ai_order->destination != target) {
        std::cerr << "Post-settlement AI order was not based on the settled public state\n";
        return false;
    }

    const CommandResult later_human_order = processor.execute(
        state, MoveArmyCommand{human_army, target}
    );
    if (later_human_order.accepted || state.orders().size() != 1 ||
        !state.orders().contains(ai_order->id)) {
        std::cerr << "A later human order changed the already-planned AI target lock\n";
        return false;
    }
    return true;
}

} // namespace

bool run_ai_smoke_tests() {
    return test_generated_scenario_excludes_human_and_neutral() &&
        test_ai_does_not_propose_unaffordable_recruitment() &&
        test_ai_planning_respects_existing_attack_target_lock() &&
        test_ai_initial_orders_wait_and_execute_next_month() &&
        test_post_settlement_ai_order_cannot_see_later_human_order();
}
