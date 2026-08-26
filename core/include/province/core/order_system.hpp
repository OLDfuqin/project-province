#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <limits>
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
    [[nodiscard]] static constexpr bool can_allocate_order_id(
        const std::uint64_t next_sequence
    ) noexcept {
        return next_sequence > 0 &&
            next_sequence < std::numeric_limits<std::uint64_t>::max() - 1;
    }

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
    [[nodiscard]] OrderOperationResult queue_war_declaration(
        GameState& state,
        const CountryId& aggressor_id,
        const CountryId& defender_id
    ) const;
    [[nodiscard]] OrderOperationResult cancel(
        GameState& state,
        const OrderId& order_id
    ) const;
};

} // namespace province::core
