#include "province/core/order_system.hpp"

#include "province/core/army_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/road_system.hpp"
#include "province/core/technology_system.hpp"

#include <limits>
#include <type_traits>
#include <utility>

namespace province::core {
namespace {

OrderOperationResult rejected(std::string error) {
    return {false, std::move(error), std::nullopt};
}

bool has_army_order(const GameState& state, const ArmyId& army_id) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* action = std::get_if<ArmyActionOrder>(&order);
        if (action != nullptr && action->army_id == army_id) return true;
    }
    return false;
}

bool has_research_order(const GameState& state, const CountryId& country_id) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* research = std::get_if<ResearchOrder>(&order);
        if (research != nullptr && research->country_id == country_id) return true;
    }
    return false;
}

bool has_road_order(
    const GameState& state,
    const ProvinceConnectionKey& connection
) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* road = std::get_if<RoadConstructionOrder>(&order);
        if (road != nullptr &&
            ProvinceConnectionKey{road->province_a, road->province_b} == connection) {
            return true;
        }
    }
    return false;
}

bool has_war_declaration_order(
    const GameState& state,
    const CountryId& country_a,
    const CountryId& country_b
) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* declaration = std::get_if<WarDeclarationOrder>(&order);
        if (declaration == nullptr) continue;
        if ((declaration->country_id == country_a &&
             declaration->defender_id == country_b) ||
            (declaration->country_id == country_b &&
             declaration->defender_id == country_a)) {
            return true;
        }
    }
    return false;
}

std::optional<CountryId> attack_lock_owner(
    const GameState& state,
    const ProvinceId& destination
) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* action = std::get_if<ArmyActionOrder>(&order);
        if (action != nullptr && action->is_attack &&
            action->destination == destination) {
            return action->country_id;
        }
    }
    return std::nullopt;
}

std::int64_t reserved_population(
    const GameState& state,
    const ProvinceId& province_id
) {
    std::int64_t reserved = 0;
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const auto* recruitment = std::get_if<RecruitmentOrder>(&order);
        if (recruitment == nullptr || recruitment->province_id != province_id) continue;
        if (recruitment->manpower > std::numeric_limits<std::int64_t>::max() - reserved) {
            return std::numeric_limits<std::int64_t>::max();
        }
        reserved += recruitment->manpower;
    }
    return reserved;
}

} // namespace

OrderOperationResult OrderSystem::queue_army_action(
    GameState& state,
    const ArmyId& army_id,
    const std::vector<ProvinceId>& path,
    const bool is_attack
) const {
    Army* army = state.find_army(army_id);
    if (army == nullptr) return rejected("ordered army does not exist");
    const Country* owner = state.find_country(army->owner_id);
    if (owner == nullptr) return rejected("ordered army owner does not exist");
    if (owner->hidden) return rejected("hidden neutral country cannot queue army actions");
    if (has_army_order(state, army_id)) {
        return rejected("army already has an action order");
    }
    if (path.size() < 2 || path.front() != army->province_id) {
        return rejected("army action path must start at the army's current province");
    }

    for (std::size_t index = 1; index < path.size(); ++index) {
        if (!state.are_adjacent(path[index - 1], path[index])) {
            return rejected("army action path contains non-adjacent provinces");
        }
        const Province* destination = state.find_province(path[index]);
        if (destination == nullptr) {
            return rejected("army action path references an unknown province");
        }
        if (index + 1 < path.size() && state.controller_of(path[index]) != army->owner_id) {
            return rejected("army action path crosses a province not controlled by its country");
        }
    }
    std::int64_t cost_half = MovementSystem{}.path_cost_half(state, path);
    const CountryId target_controller = state.controller_of(path.back());
    if (is_attack) {
        if (!state.are_hostile(army->owner_id, target_controller)) {
            return rejected("attack target is not hostile to the army owner");
        }
        const std::optional<CountryId> lock_owner = attack_lock_owner(state, path.back());
        if (lock_owner.has_value() && *lock_owner != army->owner_id) {
            return rejected("attack target is already locked by another country");
        }
        cost_half += 2 * MovementSystem::movement_point_scale;
    } else if (target_controller != army->owner_id) {
        return rejected("ordinary movement target is not controlled by the army owner");
    }
    if (cost_half <= 0 || cost_half > std::numeric_limits<std::int32_t>::max()) {
        return rejected("army action movement reservation is out of range");
    }
    if (army->movement_points < cost_half) {
        return rejected("army has insufficient movement points for the action order");
    }
    if (!can_allocate_order_id(state.next_order_sequence_)) {
        return rejected("order ID sequence is exhausted");
    }

    const OrderId id{"order_" + std::to_string(state.next_order_sequence_)};
    ArmyActionOrder order{
        id,
        army_id,
        army->owner_id,
        path.front(),
        path.back(),
        path,
        static_cast<std::int32_t>(cost_half),
        is_attack,
    };
    const auto [iterator, inserted] = state.orders_.emplace(id, std::move(order));
    static_cast<void>(iterator);
    if (!inserted) return rejected("generated duplicate order ID");
    army->movement_points -= static_cast<std::int32_t>(cost_half);
    ++state.next_order_sequence_;
    return {true, {}, id};
}

OrderOperationResult OrderSystem::queue_recruitment(
    GameState& state,
    const CountryId& country_id,
    const ProvinceId& province_id,
    const std::int64_t manpower
) const {
    Country* country = state.find_country(country_id);
    const Province* province = state.find_province(province_id);
    if (country == nullptr) return rejected("recruiting country does not exist");
    if (country->hidden) return rejected("hidden neutral country cannot recruit");
    if (country->treasury < 0) return rejected("country in debt cannot queue paid projects");
    if (province == nullptr) return rejected("recruitment province does not exist");
    if (state.controller_of(province_id) != country_id) {
        return rejected("recruitment province is not controlled by the country");
    }
    if (manpower <= 0) return rejected("recruitment manpower must be positive");
    if (manpower > std::numeric_limits<std::int64_t>::max() /
            ArmySystem::recruitment_cost_per_soldier) {
        return rejected("recruitment cost overflow");
    }
    const std::int64_t already_reserved = reserved_population(state, province_id);
    if (already_reserved > province->population ||
        manpower > province->population - already_reserved ||
        already_reserved > province->recruitable_population ||
        manpower > province->recruitable_population - already_reserved) {
        return rejected("province population available for recruitment is insufficient");
    }
    const std::int64_t cost = manpower * ArmySystem::recruitment_cost_per_soldier;
    if (country->treasury < cost) {
        return rejected("country treasury is insufficient for recruitment");
    }
    if (!can_allocate_order_id(state.next_order_sequence_)) {
        return rejected("order ID sequence is exhausted");
    }

    const OrderId id{"order_" + std::to_string(state.next_order_sequence_)};
    const auto [iterator, inserted] = state.orders_.emplace(
        id,
        RecruitmentOrder{id, country_id, province_id, manpower, cost, 1}
    );
    static_cast<void>(iterator);
    if (!inserted) return rejected("generated duplicate order ID");
    country->treasury -= cost;
    ++state.next_order_sequence_;
    return {true, {}, id};
}

OrderOperationResult OrderSystem::queue_road_construction(
    GameState& state,
    const CountryId& country_id,
    const ProvinceId& province_a,
    const ProvinceId& province_b
) const {
    Country* country = state.find_country(country_id);
    if (country == nullptr) return rejected("road builder country does not exist");
    if (country->hidden) return rejected("hidden neutral country cannot build roads");
    if (country->treasury < 0) return rejected("country in debt cannot queue paid projects");
    const Province* first = state.find_province(province_a);
    const Province* second = state.find_province(province_b);
    if (first == nullptr || second == nullptr) {
        return rejected("both road endpoint provinces must exist");
    }
    if (!state.are_adjacent(province_a, province_b)) {
        return rejected("road endpoint provinces are not adjacent");
    }
    if (state.controller_of(province_a) != country_id ||
        state.controller_of(province_b) != country_id) {
        return rejected("road endpoint provinces must be controlled by the paying country");
    }
    const ProvinceConnectionKey connection{province_a, province_b};
    if (state.road_level(province_a, province_b) != RoadLevel::none) {
        return rejected("a paved road already exists on this connection");
    }
    if (has_road_order(state, connection)) {
        return rejected("a road construction order already exists on this connection");
    }
    const CountryTechnology* technology = state.find_technology(country_id);
    if (technology == nullptr) return rejected("road builder has no technology state");
    const std::int32_t required_level =
        RoadSystem::required_roads_level(first->terrain, second->terrain);
    if (technology->roads_level < required_level) {
        return rejected("road technology level is insufficient for these terrain endpoints");
    }
    const std::int64_t base_cost = RoadSystem::endpoint_base_cost(first->terrain) +
        RoadSystem::endpoint_base_cost(second->terrain);
    const std::int64_t cost = base_cost *
        (100 - RoadSystem::discount_percent(technology->roads_level)) / 100;
    if (country->treasury < cost) {
        return rejected("country treasury is insufficient to build the road");
    }
    if (!can_allocate_order_id(state.next_order_sequence_)) {
        return rejected("order ID sequence is exhausted");
    }

    const OrderId id{"order_" + std::to_string(state.next_order_sequence_)};
    const auto [iterator, inserted] = state.orders_.emplace(
        id,
        RoadConstructionOrder{id, country_id, province_a, province_b, cost, 1}
    );
    static_cast<void>(iterator);
    if (!inserted) return rejected("generated duplicate order ID");
    country->treasury -= cost;
    ++state.next_order_sequence_;
    return {true, {}, id};
}

OrderOperationResult OrderSystem::queue_research(
    GameState& state,
    const CountryId& country_id,
    const TechnologyTrack track
) const {
    Country* country = state.find_country(country_id);
    const CountryTechnology* technology = state.find_technology(country_id);
    if (country == nullptr || technology == nullptr) {
        return rejected("researching country does not exist");
    }
    if (country->hidden) return rejected("hidden neutral country cannot research");
    if (country->treasury < 0) return rejected("country in debt cannot queue paid projects");
    if (has_research_order(state, country_id)) {
        return rejected("country already has a research order");
    }
    const std::int32_t previous_level = technology->level(track);
    if (previous_level >= TechnologySystem::maximum_level(track)) {
        return rejected("technology track is already at maximum level");
    }
    const std::int32_t target_level = previous_level + 1;
    const std::int64_t cost = TechnologySystem::research_cost(previous_level);
    if (country->treasury < cost) {
        return rejected("country treasury is insufficient for research");
    }
    if (!can_allocate_order_id(state.next_order_sequence_)) {
        return rejected("order ID sequence is exhausted");
    }

    const OrderId id{"order_" + std::to_string(state.next_order_sequence_)};
    const auto [iterator, inserted] = state.orders_.emplace(
        id,
        ResearchOrder{
            id,
            country_id,
            track,
            previous_level,
            target_level,
            cost,
            target_level + 1,
        }
    );
    static_cast<void>(iterator);
    if (!inserted) return rejected("generated duplicate order ID");
    country->treasury -= cost;
    ++state.next_order_sequence_;
    return {true, {}, id};
}

OrderOperationResult OrderSystem::queue_war_declaration(
    GameState& state,
    const CountryId& aggressor_id,
    const CountryId& defender_id
) const {
    if (aggressor_id == defender_id) {
        return rejected("a country cannot declare war on itself");
    }
    const Country* aggressor = state.find_country(aggressor_id);
    const Country* defender = state.find_country(defender_id);
    if (aggressor == nullptr) return rejected("aggressor country does not exist");
    if (defender == nullptr) return rejected("defender country does not exist");
    if (aggressor->hidden || defender->hidden) {
        return rejected("hidden neutral country cannot participate in diplomacy");
    }
    if (state.are_at_war(aggressor_id, defender_id)) {
        return rejected("countries are already at war");
    }
    if (has_war_declaration_order(state, aggressor_id, defender_id)) {
        return rejected("countries already have a pending war declaration");
    }
    if (!can_allocate_order_id(state.next_order_sequence_)) {
        return rejected("order ID sequence is exhausted");
    }

    const OrderId id{"order_" + std::to_string(state.next_order_sequence_)};
    const auto [iterator, inserted] = state.orders_.emplace(
        id,
        WarDeclarationOrder{id, aggressor_id, defender_id}
    );
    static_cast<void>(iterator);
    if (!inserted) return rejected("generated duplicate order ID");
    ++state.next_order_sequence_;
    return {true, {}, id};
}

OrderOperationResult OrderSystem::cancel(
    GameState& state,
    const OrderId& id
) const {
    const auto iterator = state.orders_.find(id);
    if (iterator == state.orders_.end()) return rejected("order does not exist");

    std::string error;
    std::visit([&](const auto& order) {
        using OrderType = std::decay_t<decltype(order)>;
        if constexpr (std::is_same_v<OrderType, ArmyActionOrder>) {
            Army* army = state.find_army(order.army_id);
            if (army == nullptr ||
                army->movement_points > std::numeric_limits<std::int32_t>::max() -
                    order.reserved_movement_half) {
                error = "cannot refund movement to the ordered army";
            } else {
                army->movement_points += order.reserved_movement_half;
            }
        } else if constexpr (std::is_same_v<OrderType, WarDeclarationOrder>) {
            // Diplomacy intent has no prepaid resource to refund.
        } else {
            Country* country = state.find_country(order.country_id);
            if (country == nullptr) {
                error = "cannot refund an order whose country does not exist";
                return;
            }
            std::int64_t refund = order.paid_cost;
            if constexpr (std::is_same_v<OrderType, ResearchOrder>) {
                if (order.remaining_months != order.target_level + 1) refund = 0;
            }
            if (refund > 0 && country->treasury >
                    std::numeric_limits<std::int64_t>::max() - refund) {
                error = "order refund would overflow the country treasury";
            } else {
                country->treasury += refund;
            }
        }
    }, iterator->second);
    if (!error.empty()) return rejected(std::move(error));

    state.orders_.erase(iterator);
    return {true, {}, id};
}

} // namespace province::core
