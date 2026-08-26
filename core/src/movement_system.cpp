#include "province/core/movement_system.hpp"

#include <algorithm>
#include <limits>
#include <map>
#include <queue>
#include <stdexcept>

namespace province::core {
namespace {

std::int32_t reserved_movement_half(
    const GameState& state,
    const ArmyId& army_id
) noexcept {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* action = std::get_if<ArmyActionOrder>(&order);
        if (action != nullptr && action->army_id == army_id) {
            return action->reserved_movement_half;
        }
    }
    return 0;
}

std::int32_t edge_cost_half(
    const GameState& state,
    const ProvinceId& origin,
    const ProvinceId& destination
) {
    const Province* province = state.find_province(destination);
    if (province == nullptr || !state.are_adjacent(origin, destination)) {
        throw std::invalid_argument{"movement path contains an invalid edge"};
    }
    const std::int32_t cost = state.road_level(origin, destination) == RoadLevel::paved
        ? MovementSystem::paved_road_cost
        : terrain_movement_cost(province->terrain);
    return cost * MovementSystem::movement_point_scale;
}

} // namespace

MonthlyMovementReport MovementSystem::grant_monthly_points(GameState& state) const {
    MonthlyMovementReport report;
    report.grants.reserve(state.army_count());
    for (const auto& [army_id, army_snapshot] : state.armies()) {
        Army* army = state.find_army(army_id);
        if (army == nullptr) {
            throw std::logic_error{"army disappeared during movement point grant"};
        }
        const Country* owner = state.find_country(army->owner_id);
        if (owner != nullptr && owner->hidden) {
            army->movement_points = 0;
            continue;
        }
        const CountryTechnology* technology = state.find_technology(army->owner_id);
        if (technology == nullptr) {
            throw std::logic_error{"army owner has no technology state"};
        }
        const std::int32_t granted_points = monthly_movement_points_half(
            technology->military_level
        );
        const std::int32_t movement_cap = maximum_movement_points_half(
            technology->military_level
        );
        const std::int32_t reserved_points = reserved_movement_half(state, army_id);
        const std::int32_t available_cap = std::max(0, movement_cap - reserved_points);
        if (army_snapshot.movement_points >
            std::numeric_limits<std::int32_t>::max() - granted_points) {
            throw std::overflow_error{"army movement point overflow"};
        }
        army->movement_points = std::min(
            available_cap,
            army->movement_points + granted_points
        );
        report.grants.push_back(ArmyMovementGrant{
            army_id,
            granted_points,
            army->movement_points,
        });
    }
    return report;
}

std::int32_t MovementSystem::path_cost_half(
    const GameState& state,
    const std::vector<ProvinceId>& path
) const {
    if (path.size() < 2) {
        throw std::invalid_argument{"movement path must contain at least one edge"};
    }
    std::int64_t total = 0;
    for (std::size_t index = 1; index < path.size(); ++index) {
        total += edge_cost_half(state, path[index - 1], path[index]);
        if (total > std::numeric_limits<std::int32_t>::max()) {
            throw std::overflow_error{"movement path cost overflow"};
        }
    }
    return static_cast<std::int32_t>(total);
}

std::vector<ProvinceId> MovementSystem::find_order_path(
    const GameState& state,
    const ArmyId& army_id,
    const ProvinceId& destination
) const {
    const Army* army = state.find_army(army_id);
    const Province* destination_province = state.find_province(destination);
    if (army == nullptr || destination_province == nullptr ||
        army->province_id == destination) {
        return {};
    }
    const Country* owner = state.find_country(army->owner_id);
    if (owner == nullptr || owner->hidden) {
        return {};
    }
    const CountryId destination_controller = state.controller_of(destination);
    const bool is_attack = destination_controller != army->owner_id;
    if (is_attack && !state.are_hostile(army->owner_id, destination_controller)) {
        return {};
    }

    using QueueItem = std::pair<std::int32_t, ProvinceId>;
    std::priority_queue<QueueItem, std::vector<QueueItem>, std::greater<>> frontier;
    std::map<ProvinceId, std::int32_t> distances;
    std::map<ProvinceId, ProvinceId> previous;
    distances.emplace(army->province_id, 0);
    frontier.emplace(0, army->province_id);

    while (!frontier.empty()) {
        const auto [distance, current_id] = frontier.top();
        frontier.pop();
        if (distances.at(current_id) != distance) {
            continue;
        }
        if (current_id == destination) {
            break;
        }
        const Province* current = state.find_province(current_id);
        if (current == nullptr) {
            continue;
        }
        for (const ProvinceId& neighbor_id : current->neighbors) {
            if (neighbor_id != destination &&
                state.controller_of(neighbor_id) != army->owner_id) {
                continue;
            }
            const std::int32_t edge = edge_cost_half(state, current_id, neighbor_id);
            if (distance > std::numeric_limits<std::int32_t>::max() - edge) {
                continue;
            }
            const std::int32_t candidate = distance + edge;
            const auto existing = distances.find(neighbor_id);
            if (existing == distances.end() || candidate < existing->second) {
                distances.insert_or_assign(neighbor_id, candidate);
                previous.insert_or_assign(neighbor_id, current_id);
                frontier.emplace(candidate, neighbor_id);
            }
        }
    }

    const auto found = distances.find(destination);
    const std::int32_t attack_surcharge = is_attack ? 2 * movement_point_scale : 0;
    if (found == distances.end() || found->second > army->movement_points - attack_surcharge) {
        return {};
    }

    std::vector<ProvinceId> reversed_path{destination};
    ProvinceId current = destination;
    while (current != army->province_id) {
        const auto predecessor = previous.find(current);
        if (predecessor == previous.end()) {
            return {};
        }
        current = predecessor->second;
        reversed_path.push_back(current);
    }
    return {reversed_path.rbegin(), reversed_path.rend()};
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
    if (reserved_movement_half(state, army_id) > 0) {
        return {
            false,
            "army with a pending action order cannot move immediately",
            origin,
            destination,
            0,
        };
    }
    const Country* moving_country = state.find_country(army->owner_id);
    if (moving_country == nullptr || moving_country->hidden) {
        return {false, "hidden neutral armies cannot move", origin, destination, 0};
    }
    if (destination_province == nullptr) {
        return {false, "movement destination does not exist", origin, destination, 0};
    }
    if (!state.are_adjacent(origin, destination)) {
        return {false, "army can only move to an adjacent province", origin, destination, 0};
    }
    const CountryId destination_controller = state.controller_of(destination);
    if (destination_controller != army->owner_id &&
        !state.are_hostile(army->owner_id, destination_controller)) {
        return {
            false,
            "army cannot enter foreign territory without war or military access",
            origin,
            destination,
            0,
        };
    }

    const std::int32_t cost_half = edge_cost_half(state, origin, destination);
    const std::int32_t cost = cost_half / movement_point_scale;
    if (army->movement_points < cost_half) {
        return {false, "army has insufficient movement points", origin, destination, cost};
    }

    army->movement_points -= cost_half;
    army->province_id = destination;
    return {true, {}, origin, destination, cost};
}

} // namespace province::core
