#include "province/core/battle_system.hpp"

#include <algorithm>
#include <map>
#include <random>
#include <stdexcept>
#include <string>
#include <utility>

namespace province::core {

namespace {

std::int32_t default_random_roll() {
    static std::mt19937 engine{std::random_device{}()};
    static std::uniform_int_distribution<std::int32_t> distribution{7, 14};
    return distribution(engine);
}

const CountryTechnology& technology_for(
    const GameState& state,
    const CountryId& country_id
) {
    const CountryTechnology* technology = state.find_technology(country_id);
    if (technology == nullptr) {
        throw std::logic_error{"army owner has no technology state"};
    }
    return *technology;
}

void validate_application_targets(
    const GameState& state,
    const ArmyId& attacker_army_id,
    const std::int64_t attacker_manpower,
    const std::vector<DefenderBattleInput>& defenders,
    const BattleCalculation& calculation
) {
    const Army* attacker = state.find_army(attacker_army_id);
    if (attacker == nullptr || attacker->manpower != attacker_manpower) {
        throw std::logic_error{"attacking army changed during battle calculation"};
    }
    if (calculation.attacker_initial_manpower != attacker_manpower ||
        calculation.attacker_casualties < 0 ||
        calculation.attacker_casualties > attacker_manpower ||
        calculation.attacker_remaining_manpower !=
            attacker_manpower - calculation.attacker_casualties) {
        throw std::logic_error{"battle calculation does not match attacker snapshot"};
    }
    if (calculation.defender_losses.size() != defenders.size()) {
        throw std::logic_error{"battle calculation does not map every defender"};
    }
    for (const DefenderBattleInput& defender : defenders) {
        const auto loss = std::find_if(
            calculation.defender_losses.begin(),
            calculation.defender_losses.end(),
            [&defender](const DefenderBattleLoss& candidate) {
                return candidate.army_id == defender.army_id;
            }
        );
        if (loss == calculation.defender_losses.end() || loss->casualties < 0 ||
            loss->casualties > defender.manpower ||
            loss->remaining_manpower != defender.manpower - loss->casualties) {
            throw std::logic_error{"battle calculation does not match defender snapshot"};
        }
        const Army* current = state.find_army(defender.army_id);
        if (current == nullptr || current->manpower != defender.manpower) {
            throw std::logic_error{"defending army changed during battle calculation"};
        }
    }
}

} // namespace

BattleSystem::BattleSystem(RandomRoll random_roll)
    : random_roll_(random_roll ? std::move(random_roll) : RandomRoll{default_random_roll}) {}

BattleResolution BattleSystem::resolve_entry(
    GameState& state,
    const ArmyId& attacker_army_id,
    const ProvinceId& attacker_origin
) const {
    Army* attacker = state.find_army(attacker_army_id);
    if (attacker == nullptr) {
        throw std::invalid_argument{"attacking army does not exist"};
    }

    const ProvinceId battle_province = attacker->province_id;
    const CountryId attacker_country = attacker->owner_id;
    const std::int64_t attacker_manpower = attacker->manpower;
    std::map<ArmyId, std::string> display_names;
    display_names.emplace(
        attacker_army_id,
        state.army_display_name(attacker_army_id)
    );
    std::vector<DefenderBattleInput> defenders;
    CountryId defender_country = state.controller_of(battle_province);
    for (const auto& [army_id, army] : state.armies()) {
        if (army_id == attacker_army_id || army.province_id != battle_province ||
            army.owner_id == attacker_country ||
            !state.are_at_war(attacker_country, army.owner_id)) {
            continue;
        }
        const CountryTechnology& technology = technology_for(state, army.owner_id);
        display_names.emplace(army_id, state.army_display_name(army_id));
        defenders.push_back({army_id, army.owner_id, army.manpower, technology.military_level});
    }

    if (defenders.empty()) {
        BattleResolution result{
            false, battle_province, attacker_country, defender_country
        };
        result.result = BattleResultType::attacker_victory;
        result.attacker_won = true;
        if (state.controller_of(battle_province) != attacker_country) {
            state.set_occupation(battle_province, attacker_country);
            result.province_occupied = true;
        }
        return result;
    }

    defender_country = defenders.front().country_id;
    const Province* battlefield = state.find_province(battle_province);
    if (battlefield == nullptr) {
        throw std::logic_error{"battle province disappeared"};
    }
    const CountryTechnology& attacker_technology = technology_for(state, attacker_country);
    const std::int32_t attacker_roll = random_roll_();
    const std::int32_t defender_roll = random_roll_();
    const BattleCalculation calculation = BattleCalculator::calculate({
        attacker_manpower,
        attacker_technology.military_level,
        defenders,
        terrain_defense_bonus(battlefield->terrain),
        attacker_roll,
        defender_roll,
    });

    BattleResolution result{
        true, battle_province, attacker_country, defender_country
    };
    result.result = calculation.result;
    result.attacker_won = calculation.result == BattleResultType::attacker_victory;
    result.attacker_random_tenths = calculation.attacker_random_tenths;
    result.defender_random_tenths = calculation.defender_random_tenths;
    result.attacker_initial_manpower = calculation.attacker_initial_manpower;
    result.defender_initial_manpower = calculation.defender_initial_manpower;
    result.attacker_military_level = calculation.attacker_military_level;
    result.defender_military_level = calculation.defender_military_level;
    result.terrain_defense_bonus = calculation.terrain_defense_bonus;
    result.attacker_base_strength = calculation.attacker_base_strength;
    result.defender_base_strength = calculation.defender_base_strength;
    result.defender_final_strength = calculation.defender_final_strength;
    result.attacker_casualties = calculation.attacker_casualties;
    result.defender_casualties = calculation.defender_casualties;
    result.attacker_remaining_manpower = calculation.attacker_remaining_manpower;
    result.defender_remaining_manpower = calculation.defender_remaining_manpower;

    validate_application_targets(
        state,
        attacker_army_id,
        attacker_manpower,
        defenders,
        calculation
    );

    Army* attacker_to_apply = state.find_army(attacker_army_id);
    attacker_to_apply->manpower = calculation.attacker_remaining_manpower;
    result.armies.push_back({
        attacker_army_id,
        display_names.at(attacker_army_id),
        calculation.attacker_casualties,
        calculation.attacker_remaining_manpower,
        std::nullopt,
        calculation.attacker_remaining_manpower == 0,
    });
    if (calculation.attacker_remaining_manpower == 0) {
        state.remove_army(attacker_army_id);
    }

    for (const DefenderBattleLoss& loss : calculation.defender_losses) {
        Army* defender = state.find_army(loss.army_id);
        if (defender == nullptr) {
            throw std::logic_error{"defending army disappeared during battle"};
        }
        defender->manpower = loss.remaining_manpower;
        result.armies.push_back({
            loss.army_id,
            display_names.at(loss.army_id),
            loss.casualties,
            loss.remaining_manpower,
            std::nullopt,
            loss.remaining_manpower == 0,
        });
        if (loss.remaining_manpower == 0) {
            state.remove_army(loss.army_id);
        }
    }

    if (calculation.result == BattleResultType::defender_victory) {
        Army* surviving_attacker = state.find_army(attacker_army_id);
        if (surviving_attacker != nullptr) {
            surviving_attacker->province_id = attacker_origin;
            result.armies.front().retreat_province = attacker_origin;
        }
    } else if (calculation.result == BattleResultType::attacker_victory &&
               state.find_army(attacker_army_id) != nullptr &&
               state.controller_of(battle_province) != attacker_country) {
        state.set_occupation(battle_province, attacker_country);
        result.province_occupied = true;
    }

    return result;
}

} // namespace province::core
