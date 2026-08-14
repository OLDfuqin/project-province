#include "province/core/army_system.hpp"

#include <limits>
#include <set>

namespace province::core {

ArmyRecruitResult ArmySystem::recruit(
    GameState& state,
    const CountryId& country_id,
    const ProvinceId& province_id,
    const std::int64_t manpower
) const {
    if (manpower <= 0) {
        return {false, "recruitment manpower must be positive", 0, std::nullopt};
    }
    if (manpower > std::numeric_limits<std::int64_t>::max() /
            recruitment_cost_per_soldier) {
        return {false, "recruitment cost overflow", 0, std::nullopt};
    }

    Country* country = state.find_country(country_id);
    Province* province = state.find_province(province_id);
    if (country == nullptr) {
        return {false, "recruiting country does not exist", 0, std::nullopt};
    }
    if (province == nullptr) {
        return {false, "recruitment province does not exist", 0, std::nullopt};
    }
    if (state.controller_of(province_id) != country_id) {
        return {false, "recruitment province is not controlled by the country", 0, std::nullopt};
    }
    if (province->recruitable_population < manpower) {
        return {false, "province recruitable population is insufficient", 0, std::nullopt};
    }
    if (province->population < manpower) {
        return {false, "province population is insufficient", 0, std::nullopt};
    }

    const std::int64_t cost = manpower * recruitment_cost_per_soldier;
    if (country->treasury < cost) {
        return {false, "country treasury is insufficient for recruitment", 0, std::nullopt};
    }

    country->treasury -= cost;
    province->recruitable_population -= manpower;
    province->population -= manpower;
    const ArmyId army_id = state.create_army(country_id, province_id, manpower);
    return {true, {}, cost, army_id};
}

ArmyRenameResult ArmySystem::rename(
    GameState& state,
    const ArmyId& army_id,
    const std::int64_t formation_number
) const {
    Army* army = state.find_army(army_id);
    if (army == nullptr) {
        return {false, "army does not exist", CountryId{"unknown"}, 0, 0};
    }
    if (formation_number <= 0) {
        return {
            false,
            "formation number must be positive",
            army->owner_id,
            army->formation_number,
            army->formation_number,
        };
    }
    for (const auto& [other_id, other] : state.armies()) {
        if (other_id != army_id && other.owner_id == army->owner_id &&
            other.formation_number == formation_number) {
            return {
                false,
                "formation number is already used by this country",
                army->owner_id,
                army->formation_number,
                army->formation_number,
            };
        }
    }
    const std::int64_t previous = army->formation_number;
    army->formation_number = formation_number;
    return {true, {}, army->owner_id, previous, formation_number};
}

ArmyMergeResult ArmySystem::merge(
    GameState& state,
    const ArmyId& primary_army_id,
    const std::vector<ArmyId>& merged_army_ids
) const {
    Army* primary = state.find_army(primary_army_id);
    if (primary == nullptr) {
        return {false, "primary army does not exist", 0, 0, 0};
    }
    if (merged_army_ids.empty()) {
        return {false, "at least one army must be merged", 0, 0, 0};
    }

    std::set<ArmyId> unique_ids;
    std::int64_t total_manpower = primary->manpower;
    std::int32_t minimum_movement_points = primary->movement_points;
    for (const ArmyId& merged_id : merged_army_ids) {
        if (merged_id == primary_army_id) {
            return {false, "primary army cannot merge into itself", 0, 0, 0};
        }
        if (!unique_ids.insert(merged_id).second) {
            return {false, "merged army list contains duplicates", 0, 0, 0};
        }
        const Army* merged = state.find_army(merged_id);
        if (merged == nullptr) {
            return {false, "merged army does not exist", 0, 0, 0};
        }
        if (merged->owner_id != primary->owner_id) {
            return {false, "armies must belong to the same country", 0, 0, 0};
        }
        if (merged->province_id != primary->province_id) {
            return {false, "armies must occupy the same province", 0, 0, 0};
        }
        if (total_manpower >
            std::numeric_limits<std::int64_t>::max() - merged->manpower) {
            return {false, "merged army manpower overflow", 0, 0, 0};
        }
        total_manpower += merged->manpower;
        minimum_movement_points =
            std::min(minimum_movement_points, merged->movement_points);
    }

    const std::int64_t previous_manpower = primary->manpower;
    primary->manpower = total_manpower;
    primary->movement_points = minimum_movement_points;
    for (const ArmyId& merged_id : merged_army_ids) {
        state.remove_army(merged_id);
    }
    return {
        true,
        {},
        previous_manpower,
        total_manpower,
        minimum_movement_points,
    };
}

} // namespace province::core
