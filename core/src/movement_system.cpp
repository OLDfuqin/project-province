#include "province/core/movement_system.hpp"

#include <limits>
#include <stdexcept>

namespace province::core {

MonthlyMovementReport MovementSystem::grant_monthly_points(GameState& state) const {
    MonthlyMovementReport report;
    report.grants.reserve(state.army_count());
    for (const auto& [army_id, army_snapshot] : state.armies()) {
        Army* army = state.find_army(army_id);
        if (army == nullptr) {
            throw std::logic_error{"army disappeared during movement point grant"};
        }
        const CountryTechnology* technology = state.find_technology(army->owner_id);
        if (technology == nullptr) {
            throw std::logic_error{"army owner has no technology state"};
        }
        const std::int32_t granted_points =
            monthly_movement_points + technology->roads_level;
        if (army_snapshot.movement_points >
            std::numeric_limits<std::int32_t>::max() - granted_points) {
            throw std::overflow_error{"army movement point overflow"};
        }
        army->movement_points += granted_points;
        report.grants.push_back(ArmyMovementGrant{
            army_id,
            granted_points,
            army->movement_points,
        });
    }
    return report;
}

ArmyMoveResult MovementSystem::move(
    GameState& state,
    const ArmyId& army_id,
    const ProvinceId& destination
) const {
    Army* army = state.find_army(army_id);
    const Province* destination_province = state.find_province(destination);
    if (army == nullptr) {
        return {false, "army does not exist", destination, destination, 0};
    }
    const ProvinceId origin = army->province_id;
    if (destination_province == nullptr) {
        return {false, "movement destination does not exist", origin, destination, 0};
    }
    if (!state.are_adjacent(origin, destination)) {
        return {false, "army can only move to an adjacent province", origin, destination, 0};
    }
    const CountryId destination_controller = state.controller_of(destination);
    if (destination_controller != army->owner_id &&
        !state.are_at_war(army->owner_id, destination_controller)) {
        return {
            false,
            "army cannot enter foreign territory without war or military access",
            origin,
            destination,
            0,
        };
    }

    const std::int32_t cost =
        state.road_level(origin, destination) == RoadLevel::paved
            ? paved_road_cost
            : terrain_movement_cost(destination_province->terrain);
    if (army->movement_points < cost) {
        return {false, "army has insufficient movement points", origin, destination, cost};
    }

    army->movement_points -= cost;
    army->province_id = destination;
    return {true, {}, origin, destination, cost};
}

} // namespace province::core
