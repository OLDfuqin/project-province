#include "province/core/battle_system.hpp"

#include <algorithm>
#include <stdexcept>

namespace province::core {

namespace {

std::int64_t effective_strength(
    const GameState& state,
    const CountryId& country_id,
    const std::int64_t manpower
) {
    const CountryTechnology* technology = state.find_technology(country_id);
    if (technology == nullptr) {
        throw std::logic_error{"army owner has no technology state"};
    }
    return manpower * (100 + 10 * technology->military_level) / 100;
}

} // namespace

std::optional<ProvinceId> BattleSystem::find_retreat_province(
    const GameState& state,
    const CountryId& country_id,
    const ProvinceId& battle_province,
    const ProvinceId& excluded_province
) {
    const Province* province = state.find_province(battle_province);
    if (province == nullptr) {
        return std::nullopt;
    }
    for (const ProvinceId& neighbor_id : province->neighbors) {
        if (neighbor_id != excluded_province &&
            state.controller_of(neighbor_id) == country_id) {
            return neighbor_id;
        }
    }
    return std::nullopt;
}

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
    std::vector<ArmyId> defender_ids;
    std::int64_t defender_strength = 0;
    CountryId defender_country = state.controller_of(battle_province);
    for (const auto& [army_id, army] : state.armies()) {
        if (army_id != attacker_army_id && army.province_id == battle_province &&
            army.owner_id != attacker_country &&
            state.are_at_war(attacker_country, army.owner_id)) {
            defender_ids.push_back(army_id);
            defender_strength += effective_strength(state, army.owner_id, army.manpower);
            defender_country = army.owner_id;
        }
    }
    if (defender_ids.empty()) {
        BattleResolution result{
            false, battle_province, attacker_country, defender_country, true, false, {}
        };
        if (state.controller_of(battle_province) != attacker_country) {
            state.set_occupation(battle_province, attacker_country);
            result.province_occupied = true;
        }
        return result;
    }

    const std::int64_t attacker_manpower = attacker->manpower;
    const std::int64_t attacker_strength =
        effective_strength(state, attacker_country, attacker_manpower);
    const bool attacker_won = attacker_strength > defender_strength;
    const std::int64_t attacker_casualties = std::min(
        attacker_manpower,
        std::max<std::int64_t>(1, defender_strength / 4)
    );
    const std::int64_t defender_casualty_budget = std::max<std::int64_t>(
        1,
        attacker_strength / 4
    );

    BattleResolution result{
        true,
        battle_province,
        attacker_country,
        defender_country,
        attacker_won,
        false,
        {},
    };

    attacker->manpower -= attacker_casualties;
    ArmyBattleOutcome attacker_outcome{
        attacker_army_id,
        attacker_casualties,
        attacker->manpower,
        std::nullopt,
        attacker->manpower == 0,
    };
    if (attacker->manpower == 0) {
        state.remove_army(attacker_army_id);
    } else if (!attacker_won) {
        attacker->province_id = attacker_origin;
        attacker_outcome.retreat_province = attacker_origin;
    }
    result.armies.push_back(std::move(attacker_outcome));

    std::int64_t remaining_budget = defender_casualty_budget;
    for (std::size_t index = 0; index < defender_ids.size(); ++index) {
        Army* defender = state.find_army(defender_ids[index]);
        if (defender == nullptr) {
            continue;
        }
        const std::int64_t armies_left =
            static_cast<std::int64_t>(defender_ids.size() - index);
        const std::int64_t assigned = std::max<std::int64_t>(1, remaining_budget / armies_left);
        const std::int64_t casualties = std::min(defender->manpower, assigned);
        remaining_budget = std::max<std::int64_t>(0, remaining_budget - casualties);
        defender->manpower -= casualties;

        ArmyBattleOutcome outcome{
            defender->id,
            casualties,
            defender->manpower,
            std::nullopt,
            defender->manpower == 0,
        };
        if (defender->manpower == 0) {
            state.remove_army(defender_ids[index]);
        } else if (attacker_won) {
            const auto retreat = find_retreat_province(
                state,
                defender->owner_id,
                battle_province,
                attacker_origin
            );
            if (retreat.has_value()) {
                defender->province_id = *retreat;
                outcome.retreat_province = retreat;
            } else {
                state.remove_army(defender_ids[index]);
                outcome.remaining_manpower = 0;
                outcome.destroyed = true;
            }
        }
        result.armies.push_back(std::move(outcome));
    }

    if (attacker_won && state.find_army(attacker_army_id) != nullptr) {
        state.set_occupation(battle_province, attacker_country);
        result.province_occupied = true;
    }
    return result;
}

} // namespace province::core
