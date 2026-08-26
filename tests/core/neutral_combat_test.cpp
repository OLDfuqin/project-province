#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/scenario_loader.hpp"
#include "smoke_test_groups.hpp"

#include <algorithm>
#include <cstdint>
#include <iostream>
#include <memory>
#include <vector>

namespace {

province::core::GameState state() {
    return province::core::ScenarioLoader::load(
        "game/data",
        province::core::GameClock{1000, 1},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
}

province::core::BattleSystem::RandomRoll rolls(std::initializer_list<std::int32_t> values) {
    auto data = std::make_shared<std::vector<std::int32_t>>(values);
    auto index = std::make_shared<std::size_t>(0);
    return [data, index]() {
        if (*index >= data->size()) throw std::logic_error{"fixed roll exhausted"};
        return data->at((*index)++);
    };
}

province::core::ArmyId guard_id(
    const province::core::GameState& game,
    const province::core::ProvinceId& province_id
) {
    for (const auto& [army_id, army] : game.armies()) {
        if (army.owner_id == province::core::CountryId{"neutral"} &&
            army.province_id == province_id) return army_id;
    }
    throw std::logic_error{"neutral guard not found"};
}

} // namespace

bool run_neutral_combat_tests() {
    using namespace province::core;
    const CountryId auroria{"auroria"};
    const CountryId neutral{"neutral"};
    const ProvinceId origin{"cell_4_4"};
    const ProvinceId target{"cell_5_4"};

    GameState conquest = state();
    if (!conquest.are_hostile(auroria, neutral) ||
        !conquest.are_hostile(neutral, auroria) ||
        conquest.are_hostile(auroria, CountryId{"caelus"})) {
        std::cerr << "Permanent neutral hostility is incorrect\n";
        return false;
    }
    const ArmyId attacker = conquest.create_army(auroria, origin, 4'000);
    conquest.find_army(attacker)->movement_points = 12;
    CommandProcessor conquest_processor{rolls({14, 7})};
    const CommandResult conquered = conquest_processor.execute(
        conquest, MoveArmyCommand{attacker, target}
    );
    if (!conquered.accepted || conquest.find_army(attacker) == nullptr ||
        conquest.find_army(attacker)->province_id != origin ||
        conquest.find_province(target)->owner_id != neutral ||
        conquest.controller_of(target) != neutral ||
        conquest.occupations().contains(target) || conquered.events.size() != 1 ||
        conquered.events.front().type != GameEventType::order_created) {
        std::cerr << "Neutral attack did not remain queued for monthly combat\n";
        return false;
    }
    const OrderId conquest_order_id =
        std::get<OrderCreatedEvent>(conquered.events.front().payload).order_id;
    const auto* conquest_order =
        std::get_if<ArmyActionOrder>(&conquest.orders().at(conquest_order_id));
    if (conquest_order == nullptr || !conquest_order->is_attack) {
        std::cerr << "Neutral attack order lost its attack classification\n";
        return false;
    }
    const ArmyId conquered_guard = guard_id(conquest, target);
    const CommandResult conquest_advanced = conquest_processor.execute(
        conquest, AdvanceTurnCommand{1}
    );
    const auto conquest_battle = std::find_if(
        conquest_advanced.events.begin(), conquest_advanced.events.end(),
        [](const GameEvent& event) { return event.type == GameEventType::battle_resolved; }
    );
    if (!conquest_advanced.accepted || conquest_battle == conquest_advanced.events.end() ||
        conquest.find_army(conquered_guard) != nullptr ||
        conquest.find_army(attacker) == nullptr ||
        conquest.find_army(attacker)->province_id != target ||
        conquest.find_province(target)->owner_id != auroria ||
        conquest.controller_of(target) != auroria || !conquest.orders().empty()) {
        std::cerr << "Monthly neutral combat did not conquer and consume its attack order\n";
        return false;
    }

    GameState mutual = state();
    mutual.find_province(target)->population = 0;
    mutual.find_province(target)->population_growth_remainder = 0;
    const ArmyId mutual_guard = guard_id(mutual, target);
    mutual.find_army(mutual_guard)->manpower = 1;
    const ArmyId mutual_attacker = mutual.create_army(auroria, origin, 1);
    mutual.find_army(mutual_attacker)->movement_points = 12;
    CommandProcessor mutual_processor{rolls({7, 7})};
    const CommandResult mutual_result = mutual_processor.execute(
        mutual, MoveArmyCommand{mutual_attacker, target}
    );
    if (!mutual_result.accepted || mutual.find_province(target)->owner_id != neutral ||
        mutual.find_army(mutual_attacker) == nullptr ||
        mutual.find_army(mutual_attacker)->province_id != origin) {
        std::cerr << "Queued mutual-destruction attack resolved before combat phase\n";
        return false;
    }
    const CommandResult mutual_advanced = mutual_processor.execute(
        mutual, AdvanceTurnCommand{1}
    );
    if (!mutual_advanced.accepted ||
        mutual.find_army(mutual_attacker) != nullptr ||
        mutual.find_army(mutual_guard) != nullptr ||
        mutual.find_province(target)->owner_id != neutral || !mutual.orders().empty()) {
        std::cerr << "Monthly neutral mutual destruction was not resolved\n";
        return false;
    }
    GameState passive = state();
    const ArmyId passive_guard = guard_id(passive, ProvinceId{"cell_5_5"});
    passive.find_army(passive_guard)->movement_points = 12;
    const ArmyMoveResult forbidden = MovementSystem{}.move(
        passive, passive_guard, ProvinceId{"cell_5_4"}
    );
    if (forbidden.accepted) {
        std::cerr << "Neutral guard was allowed to move\n";
        return false;
    }

    GameState empty = state();
    empty.remove_army(guard_id(empty, target));
    empty.find_province(target)->population = 0;
    empty.find_province(target)->population_growth_remainder = 0;
    const ArmyId unopposed = empty.create_army(auroria, origin, 100);
    empty.find_army(unopposed)->movement_points = 12;
    const CommandResult entered = CommandProcessor{}.execute(
        empty, MoveArmyCommand{unopposed, target}
    );
    if (!entered.accepted || empty.find_province(target)->owner_id != neutral ||
        empty.occupations().contains(target) ||
        empty.find_army(unopposed)->province_id != origin || empty.orders().size() != 1) {
        std::cerr << "Unopposed neutral attack did not wait for combat phase\n";
        return false;
    }
    const CommandResult empty_advanced = CommandProcessor{}.execute(
        empty, AdvanceTurnCommand{1}
    );
    const auto occupation_battle = std::find_if(
        empty_advanced.events.begin(), empty_advanced.events.end(),
        [](const GameEvent& event) { return event.type == GameEventType::battle_resolved; }
    );
    if (!empty_advanced.accepted || occupation_battle == empty_advanced.events.end() ||
        empty.find_province(target)->owner_id != auroria ||
        empty.find_army(unopposed) == nullptr ||
        empty.find_army(unopposed)->province_id != target || !empty.orders().empty()) {
        std::cerr << "Unopposed neutral attack did not occupy during monthly combat\n";
        return false;
    }
    return true;
}
