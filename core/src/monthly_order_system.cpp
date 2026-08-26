#include "province/core/monthly_order_system.hpp"

#include "province/core/army_system.hpp"
#include "province/core/movement_system.hpp"

#include <algorithm>
#include <limits>
#include <map>
#include <optional>
#include <stdexcept>

namespace province::core {
namespace {

std::optional<std::string> invalid_path_reason(
    const GameState& state,
    const ArmyActionOrder& order,
    const Army* army
) {
    if (army == nullptr) {
        return "ordered army no longer exists";
    }
    if (army->owner_id != order.country_id) {
        return "ordered army is no longer owned by the ordering country";
    }
    if (army->province_id != order.origin) {
        return "ordered army is no longer at the stored path origin";
    }
    if (order.path.size() < 2 || order.path.front() != order.origin ||
        order.path.back() != order.destination) {
        return "stored army path endpoints are invalid";
    }
    for (std::size_t index = 1; index < order.path.size(); ++index) {
        if (state.find_province(order.path[index]) == nullptr ||
            !state.are_adjacent(order.path[index - 1], order.path[index])) {
            return "stored army path is no longer continuous";
        }
        if (index + 1 < order.path.size() &&
            state.controller_of(order.path[index]) != order.country_id) {
            return "stored army path no longer has friendly intermediate control";
        }
    }
    return std::nullopt;
}

void add_refund(Army& army, const std::int32_t refund) {
    if (refund < 0 || army.movement_points >
            std::numeric_limits<std::int32_t>::max() - refund) {
        throw std::overflow_error{"army movement refund overflow"};
    }
    army.movement_points += refund;
}

void refund_project_cost(
    GameState& state,
    const CountryId& country_id,
    const std::int64_t paid_cost
) {
    Country* country = state.find_country(country_id);
    if (country == nullptr) {
        throw std::logic_error{"project refund country no longer exists"};
    }
    if (paid_cost <= 0 || country->treasury >
            std::numeric_limits<std::int64_t>::max() - paid_cost) {
        throw std::overflow_error{"project refund would overflow country treasury"};
    }
    country->treasury += paid_cost;
}

} // namespace

MonthlyOrderMovementReport MonthlyOrderSystem::resolve_movement(GameState& state) const {
    MonthlyOrderMovementReport report;
    std::vector<OrderId> action_ids;
    action_ids.reserve(state.orders_.size());
    for (const auto& [id, order] : state.orders_) {
        if (std::holds_alternative<ArmyActionOrder>(order)) {
            action_ids.push_back(id);
        }
    }

    for (const OrderId& id : action_ids) {
        const auto found = state.orders_.find(id);
        if (found == state.orders_.end()) {
            continue;
        }
        const auto* stored = std::get_if<ArmyActionOrder>(&found->second);
        if (stored == nullptr) {
            continue;
        }
        const ArmyActionOrder order = *stored;
        Army* army = state.find_army(order.army_id);
        const std::optional<std::string> path_error =
            invalid_path_reason(state, order, army);
        if (path_error.has_value()) {
            if (army != nullptr) {
                add_refund(*army, order.reserved_movement_half);
            }
            report.refunds.push_back(RefundedArmyAction{
                id,
                order.army_id,
                army == nullptr ? 0 : order.reserved_movement_half,
                *path_error,
            });
            state.orders_.erase(found);
            continue;
        }

        const CountryId target_controller = state.controller_of(order.destination);
        bool converted_from_attack = false;
        if (order.is_attack) {
            if (target_controller == order.country_id) {
                constexpr std::int32_t attack_surcharge_half =
                    2 * MovementSystem::movement_point_scale;
                if (order.reserved_movement_half < attack_surcharge_half) {
                    add_refund(*army, order.reserved_movement_half);
                    report.refunds.push_back(RefundedArmyAction{
                        id,
                        order.army_id,
                        order.reserved_movement_half,
                        "attack reservation is smaller than its required surcharge",
                    });
                    state.orders_.erase(found);
                    continue;
                }
                add_refund(*army, attack_surcharge_half);
                converted_from_attack = true;
            } else if (state.are_hostile(order.country_id, target_controller)) {
                continue;
            } else {
                add_refund(*army, order.reserved_movement_half);
                report.refunds.push_back(RefundedArmyAction{
                    id,
                    order.army_id,
                    order.reserved_movement_half,
                    "attack target is no longer hostile",
                });
                state.orders_.erase(found);
                continue;
            }
        } else if (target_controller != order.country_id) {
            add_refund(*army, order.reserved_movement_half);
            report.refunds.push_back(RefundedArmyAction{
                id,
                order.army_id,
                order.reserved_movement_half,
                "ordinary movement target is no longer friendly",
            });
            state.orders_.erase(found);
            continue;
        }

        const std::int32_t route_cost_half = MovementSystem{}.path_cost_half(
            state,
            order.path
        );
        army->province_id = order.destination;
        if (army->advance_target.has_value() &&
            army->province_id == *army->advance_target) {
            army->advance_target.reset();
        }
        report.movements.push_back(ResolvedArmyMovement{
            id,
            order.army_id,
            order.origin,
            order.destination,
            route_cost_half,
            army->movement_points,
            converted_from_attack,
        });
        state.orders_.erase(found);
    }
    return report;
}

MonthlyOrderCombatReport MonthlyOrderSystem::resolve_combat(
    GameState& state,
    const BattleSystem& battle_system
) const {
    MonthlyOrderCombatReport report;
    using AttackGroupKey = std::pair<CountryId, ProvinceId>;
    std::map<AttackGroupKey, std::vector<ArmyActionOrder>> groups;

    std::vector<OrderId> action_ids;
    action_ids.reserve(state.orders_.size());
    for (const auto& [id, order] : state.orders_) {
        const auto* action = std::get_if<ArmyActionOrder>(&order);
        if (action != nullptr && action->is_attack) {
            action_ids.push_back(id);
        }
    }

    for (const OrderId& id : action_ids) {
        const auto found = state.orders_.find(id);
        if (found == state.orders_.end()) {
            continue;
        }
        const auto* stored = std::get_if<ArmyActionOrder>(&found->second);
        if (stored == nullptr || !stored->is_attack) {
            continue;
        }
        const ArmyActionOrder order = *stored;
        Army* army = state.find_army(order.army_id);
        std::optional<std::string> error = invalid_path_reason(state, order, army);
        if (!error.has_value() && !state.are_hostile(
                order.country_id,
                state.controller_of(order.destination)
            )) {
            error = "attack target is no longer hostile";
        }
        if (error.has_value()) {
            if (army != nullptr) {
                add_refund(*army, order.reserved_movement_half);
            }
            report.refunds.push_back({
                id,
                order.army_id,
                army == nullptr ? 0 : order.reserved_movement_half,
                *error,
            });
            state.orders_.erase(found);
            continue;
        }
        groups[{order.country_id, order.destination}].push_back(order);
    }

    for (const auto& [key, group_orders] : groups) {
        std::vector<AttackingArmyEntry> attackers;
        attackers.reserve(group_orders.size());
        std::vector<OrderId> consumed_orders;
        consumed_orders.reserve(group_orders.size());

        for (const ArmyActionOrder& order : group_orders) {
            const auto found = state.orders_.find(order.id);
            if (found == state.orders_.end()) {
                continue;
            }
            Army* army = state.find_army(order.army_id);
            std::optional<std::string> error = invalid_path_reason(state, order, army);
            if (!error.has_value() &&
                (key.first != order.country_id || key.second != order.destination ||
                 !state.are_hostile(
                     order.country_id,
                     state.controller_of(order.destination)
                 ))) {
                error = "attack group is no longer valid";
            }
            if (error.has_value()) {
                if (army != nullptr) {
                    add_refund(*army, order.reserved_movement_half);
                }
                report.refunds.push_back({
                    order.id,
                    order.army_id,
                    army == nullptr ? 0 : order.reserved_movement_half,
                    *error,
                });
                state.orders_.erase(found);
                continue;
            }

            army->province_id = order.destination;
            attackers.push_back({order.army_id, order.origin});
            consumed_orders.push_back(order.id);
        }

        if (attackers.empty()) {
            continue;
        }
        report.battles.push_back(battle_system.resolve_group(state, attackers));
        for (const AttackingArmyEntry& entry : attackers) {
            Army* attacker = state.find_army(entry.army_id);
            if (attacker != nullptr && attacker->advance_target.has_value() &&
                attacker->province_id == *attacker->advance_target) {
                attacker->advance_target.reset();
            }
        }
        for (const OrderId& id : consumed_orders) {
            state.orders_.erase(id);
        }
    }
    return report;
}

MonthlyOrderProjectReport MonthlyOrderSystem::resolve_projects(GameState& state) const {
    MonthlyOrderProjectReport report;
    std::vector<OrderId> project_ids;
    project_ids.reserve(state.orders_.size());
    for (const auto& [id, order] : state.orders_) {
        if (!std::holds_alternative<ArmyActionOrder>(order)) {
            project_ids.push_back(id);
        }
    }

    for (const OrderId& id : project_ids) {
        const auto found = state.orders_.find(id);
        if (found == state.orders_.end()) continue;

        if (auto* recruitment = std::get_if<RecruitmentOrder>(&found->second)) {
            --recruitment->remaining_months;
            if (recruitment->remaining_months > 0) continue;
            const RecruitmentOrder order = *recruitment;
            const ArmyRecruitResult result = ArmySystem{}.complete_prepaid_recruitment(
                state,
                order.country_id,
                order.province_id,
                order.manpower,
                order.paid_cost
            );
            if (result.accepted && result.army_id.has_value()) {
                report.recruitments.push_back({
                    id,
                    *result.army_id,
                    order.country_id,
                    order.province_id,
                    order.manpower,
                    order.paid_cost,
                });
            } else {
                refund_project_cost(state, order.country_id, order.paid_cost);
                report.refunds.push_back({
                    id, order.country_id, order.paid_cost, result.error,
                });
            }
            state.orders_.erase(found);
            continue;
        }

        if (auto* road = std::get_if<RoadConstructionOrder>(&found->second)) {
            --road->remaining_months;
            if (road->remaining_months > 0) continue;
            const RoadConstructionOrder order = *road;
            const RoadBuildResult result = RoadSystem{}.complete_prepaid_paved_road(
                state,
                order.country_id,
                order.province_a,
                order.province_b,
                order.paid_cost
            );
            if (result.accepted) {
                report.roads.push_back({
                    id,
                    order.country_id,
                    order.province_a,
                    order.province_b,
                    order.paid_cost,
                });
            } else {
                refund_project_cost(state, order.country_id, order.paid_cost);
                report.refunds.push_back({
                    id, order.country_id, order.paid_cost, result.error,
                });
            }
            state.orders_.erase(found);
            continue;
        }

        auto* research = std::get_if<ResearchOrder>(&found->second);
        if (research == nullptr) continue;
        --research->remaining_months;
        if (research->remaining_months > 0) continue;
        const ResearchOrder order = *research;
        const TechnologyResearchResult result =
            TechnologySystem{}.complete_prepaid_research(
                state,
                order.country_id,
                order.track,
                order.previous_level,
                order.target_level,
                order.paid_cost
            );
        if (result.accepted) {
            report.research.push_back({id, result});
        } else {
            refund_project_cost(state, order.country_id, order.paid_cost);
            report.refunds.push_back({
                id, order.country_id, order.paid_cost, result.error,
            });
        }
        state.orders_.erase(found);
    }
    return report;
}

MonthlyArmyConsolidationReport MonthlyOrderSystem::consolidate_armies(
    GameState& state
) const {
    MonthlyArmyConsolidationReport report;
    using Location = std::pair<CountryId, ProvinceId>;
    std::map<Location, std::vector<ArmyId>> locations;
    for (const auto& [army_id, army] : state.armies()) {
        locations[{army.owner_id, army.province_id}].push_back(army_id);
    }

    constexpr std::int64_t automatic_merge_limit = 1'500;
    for (const auto& [location, initial_ids] : locations) {
        static_cast<void>(initial_ids);
        while (true) {
            std::vector<ArmyId> candidates;
            for (const auto& [army_id, army] : state.armies()) {
                if (army.owner_id == location.first && army.province_id == location.second &&
                    army.manpower < automatic_merge_limit) {
                    candidates.push_back(army_id);
                }
            }
            if (candidates.size() < 2) break;
            std::sort(
                candidates.begin(),
                candidates.end(),
                [&state](const ArmyId& lhs_id, const ArmyId& rhs_id) {
                    const Army& lhs = *state.find_army(lhs_id);
                    const Army& rhs = *state.find_army(rhs_id);
                    if (lhs.manpower != rhs.manpower) return lhs.manpower < rhs.manpower;
                    return lhs_id < rhs_id;
                }
            );

            const ArmyId first_id = candidates[0];
            const ArmyId second_id = candidates[1];
            const Army& first = *state.find_army(first_id);
            const Army& second = *state.find_army(second_id);
            const bool first_survives = first.formation_number < second.formation_number ||
                (first.formation_number == second.formation_number && first_id < second_id);
            const ArmyId primary_id = first_survives ? first_id : second_id;
            const ArmyId merged_id = first_survives ? second_id : first_id;
            const ArmyMergeResult merged = ArmySystem{}.merge(
                state,
                primary_id,
                {merged_id}
            );
            if (!merged.accepted) {
                throw std::logic_error{
                    "automatic army consolidation failed: " + merged.error
                };
            }
            report.merges.push_back({
                primary_id,
                {merged_id},
                merged.previous_manpower,
                merged.current_manpower,
                merged.current_movement_points,
            });
        }
    }
    return report;
}

} // namespace province::core
