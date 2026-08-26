#pragma once

#include "province/core/stable_id.hpp"
#include "province/core/technology.hpp"

#include <cstdint>
#include <variant>
#include <vector>

namespace province::core {

struct OrderIdTag;
using OrderId = StableId<OrderIdTag>;

struct ArmyActionOrder final {
    OrderId id;
    ArmyId army_id;
    CountryId country_id;
    ProvinceId origin;
    ProvinceId destination;
    std::vector<ProvinceId> path;
    std::int32_t reserved_movement_half{};
    bool is_attack{};
};

struct RecruitmentOrder final {
    OrderId id;
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int64_t paid_cost{};
    std::int32_t remaining_months{1};
};

struct RoadConstructionOrder final {
    OrderId id;
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
    std::int64_t paid_cost{};
    std::int32_t remaining_months{1};
};

struct ResearchOrder final {
    OrderId id;
    CountryId country_id;
    TechnologyTrack track{TechnologyTrack::economy};
    std::int32_t previous_level{};
    std::int32_t target_level{};
    std::int64_t paid_cost{};
    std::int32_t remaining_months{};
};

struct WarDeclarationOrder final {
    OrderId id;
    CountryId country_id;
    CountryId defender_id;
};

using GameOrder = std::variant<
    ArmyActionOrder,
    RecruitmentOrder,
    RoadConstructionOrder,
    ResearchOrder,
    WarDeclarationOrder
>;

[[nodiscard]] inline const OrderId& order_id(const GameOrder& order) noexcept {
    return std::visit([](const auto& typed_order) -> const OrderId& {
        return typed_order.id;
    }, order);
}

} // namespace province::core
