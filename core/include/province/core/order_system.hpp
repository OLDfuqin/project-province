#pragma once

#include "province/core/game_state.hpp"

#include <optional>
#include <string>
#include <vector>

namespace province::core {

struct OrderOperationResult final {
    bool accepted{};
    std::string error;
    std::optional<OrderId> order_id;
};

class OrderSystem final {
public:
    [[nodiscard]] OrderOperationResult queue_army_action(
        GameState& state,
        const ArmyId& army_id,
        const std::vector<ProvinceId>& path,
        bool is_attack
    ) const;
    [[nodiscard]] OrderOperationResult queue_recruitment(
        GameState& state,
        const CountryId& country_id,
        const ProvinceId& province_id,
        std::int64_t manpower
    ) const;
    [[nodiscard]] OrderOperationResult queue_road_construction(
        GameState& state,
        const CountryId& country_id,
        const ProvinceId& province_a,
        const ProvinceId& province_b
    ) const;
    [[nodiscard]] OrderOperationResult queue_research(
        GameState& state,
        const CountryId& country_id,
        TechnologyTrack track
    ) const;
    [[nodiscard]] OrderOperationResult cancel(
        GameState& state,
        const OrderId& order_id
    ) const;
};

} // namespace province::core
