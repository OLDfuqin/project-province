#include "province/core/battle_system.hpp"

#include <algorithm>
#include <limits>
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
    const std::vector<AttackerBattleInput>& attackers,
    const std::vector<DefenderBattleInput>& defenders,
    const BattleCalculation& calculation
) {
    if (calculation.attacker_losses.size() != attackers.size()) {
        throw std::logic_error{"battle calculation does not map every attacker"};
    }
    std::int64_t attacker_manpower = 0;
    for (const AttackerBattleInput& attacker : attackers) {
        if (attacker_manpower > std::numeric_limits<std::int64_t>::max() -
                attacker.manpower) {
            throw std::logic_error{"attacker snapshot manpower overflowed"};
        }
        attacker_manpower += attacker.manpower;
        const auto loss = std::find_if(
            calculation.attacker_losses.begin(),
            calculation.attacker_losses.end(),
            [&attacker](const AttackerBattleLoss& candidate) {
                return candidate.army_id == attacker.army_id;
            }
        );
        if (loss == calculation.attacker_losses.end() || loss->casualties < 0 ||
            loss->casualties > attacker.manpower ||
            loss->remaining_manpower != attacker.manpower - loss->casualties) {
            throw std::logic_error{"battle calculation does not match attacker snapshot"};
        }
        const Army* current = state.find_army(attacker.army_id);
        if (current == nullptr || current->manpower != attacker.manpower) {
            throw std::logic_error{"attacking army changed during battle calculation"};
        }
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

void apply_defensive_movement_debt(Army& defender) noexcept {
    if (defender.movement_points <= 0) {
        defender.movement_points = -2;
    } else {
        defender.movement_points -= 2;
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
    return resolve_group(
        state,
        {{attacker_army_id, attacker_origin}}
    );
}

BattleResolution BattleSystem::resolve_group(
    GameState& state,
    std::vector<AttackingArmyEntry> attackers
) const {
    if (attackers.empty()) {
        throw std::invalid_argument{"attacking group cannot be empty"};
    }
    std::sort(
        attackers.begin(),
        attackers.end(),
        [](const AttackingArmyEntry& left, const AttackingArmyEntry& right) {
            return left.army_id < right.army_id;
        }
    );
    const auto duplicate = std::adjacent_find(
        attackers.begin(),
        attackers.end(),
        [](const AttackingArmyEntry& left, const AttackingArmyEntry& right) {
            return left.army_id == right.army_id;
        }
    );
    if (duplicate != attackers.end()) {
        throw std::invalid_argument{"attacking army IDs must be unique"};
    }

    const Army* first_attacker = state.find_army(attackers.front().army_id);
    if (first_attacker == nullptr) {
        throw std::invalid_argument{"attacking army does not exist"};
    }
    const ProvinceId battle_province = first_attacker->province_id;
    const CountryId attacker_country = first_attacker->owner_id;
    const CountryId target_controller = state.controller_of(battle_province);
    std::map<ArmyId, std::string> display_names;
    std::map<ArmyId, ProvinceId> origins;
    std::vector<AttackerBattleInput> attacker_inputs;
    attacker_inputs.reserve(attackers.size());
    std::int64_t attacker_manpower = 0;
    for (const AttackingArmyEntry& entry : attackers) {
        const Army* attacker = state.find_army(entry.army_id);
        if (attacker == nullptr) {
            throw std::invalid_argument{"attacking army does not exist"};
        }
        if (attacker->owner_id != attacker_country ||
            attacker->province_id != battle_province) {
            throw std::invalid_argument{
                "all grouped attackers must share an owner and battle province"
            };
        }
        if (attacker_manpower > std::numeric_limits<std::int64_t>::max() -
                attacker->manpower) {
            throw std::overflow_error{"total attacker manpower exceeds int64 range"};
        }
        attacker_manpower += attacker->manpower;
        attacker_inputs.push_back({entry.army_id, attacker->manpower});
        display_names.emplace(entry.army_id, state.army_display_name(entry.army_id));
        origins.emplace(entry.army_id, entry.origin);
    }

    std::vector<DefenderBattleInput> defenders;
    CountryId defender_country = target_controller;
    for (const auto& [army_id, army] : state.armies()) {
        if (army.province_id != battle_province || army.owner_id == attacker_country ||
            !state.are_hostile(attacker_country, army.owner_id)) {
            continue;
        }
        const CountryTechnology& technology = technology_for(state, army.owner_id);
        display_names.emplace(army_id, state.army_display_name(army_id));
        defenders.push_back({army_id, army.owner_id, army.manpower, technology.military_level});
    }

    const CountryTechnology& attacker_technology = technology_for(
        state,
        attacker_country
    );
    if (defenders.empty()) {
        BattleResolution result{
            false, battle_province, attacker_country, defender_country
        };
        result.result = BattleResultType::attacker_victory;
        result.attacker_won = true;
        result.attacker_initial_manpower = attacker_manpower;
        result.attacker_remaining_manpower = attacker_manpower;
        result.attacker_military_level = attacker_technology.military_level;
        for (const AttackerBattleInput& attacker : attacker_inputs) {
            result.armies.push_back({
                attacker.army_id,
                display_names.at(attacker.army_id),
                0,
                attacker.manpower,
                std::nullopt,
                false,
            });
        }
        if (state.controller_of(battle_province) != attacker_country) {
            const Country* defender = state.find_country(target_controller);
            if (defender != nullptr && defender->hidden) {
                state.transfer_province_ownership(battle_province, attacker_country);
            } else {
                state.set_occupation(battle_province, attacker_country);
                result.province_occupied = true;
            }
        }
        return result;
    }

    defender_country = defenders.front().country_id;
    const Province* battlefield = state.find_province(battle_province);
    if (battlefield == nullptr) {
        throw std::logic_error{"battle province disappeared"};
    }
    const std::int32_t attacker_roll = random_roll_();
    const std::int32_t defender_roll = random_roll_();
    const BattleCalculation calculation = BattleCalculator::calculate({
        attacker_inputs,
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
        attacker_inputs,
        defenders,
        calculation
    );

    for (const AttackerBattleLoss& loss : calculation.attacker_losses) {
        Army* attacker = state.find_army(loss.army_id);
        if (attacker == nullptr) {
            throw std::logic_error{"attacking army disappeared during battle"};
        }
        attacker->manpower = loss.remaining_manpower;
        std::optional<ProvinceId> retreat;
        if (calculation.result == BattleResultType::defender_victory &&
            loss.remaining_manpower > 0) {
            retreat = origins.at(loss.army_id);
            attacker->province_id = *retreat;
        }
        result.armies.push_back({
            loss.army_id,
            display_names.at(loss.army_id),
            loss.casualties,
            loss.remaining_manpower,
            retreat,
            loss.remaining_manpower == 0,
        });
        if (loss.remaining_manpower == 0) {
            state.remove_army(loss.army_id);
        }
    }

    for (const DefenderBattleLoss& loss : calculation.defender_losses) {
        Army* defender = state.find_army(loss.army_id);
        if (defender == nullptr) {
            throw std::logic_error{"defending army disappeared during battle"};
        }
        defender->manpower = loss.remaining_manpower;
        apply_defensive_movement_debt(*defender);
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

    if (calculation.result == BattleResultType::attacker_victory &&
        calculation.attacker_remaining_manpower > 0 &&
        state.controller_of(battle_province) != attacker_country) {
        const Country* defender = state.find_country(target_controller);
        if (defender != nullptr && defender->hidden) {
            state.transfer_province_ownership(battle_province, attacker_country);
        } else {
            state.set_occupation(battle_province, attacker_country);
            result.province_occupied = true;
        }
    }

    return result;
}

} // namespace province::core
