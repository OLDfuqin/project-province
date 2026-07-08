#pragma once

#include "province/core/army.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/population_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/road.hpp"

#include <cstdint>
#include <variant>

namespace province::core {

enum class GameEventType : std::uint8_t {
    economy_resolved,
    population_resolved,
    army_recruited,
    army_moved,
    movement_points_granted,
    road_built,
    war_declared,
    turn_advanced,
};

struct WarDeclaredEvent final {
    CountryId aggressor_id;
    CountryId defender_id;
};

struct TurnAdvancedEvent final {
    std::int32_t previous_year{};
    std::int32_t previous_month{};
    std::int32_t current_year{};
    std::int32_t current_month{};
    std::int32_t elapsed_months{};
};

struct EconomyResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<CountryIncome> incomes;
};

struct PopulationResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<ProvincePopulationChange> changes;
};

struct RoadBuiltEvent final {
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
    RoadLevel level{RoadLevel::none};
    std::int64_t cost{};
};

struct ArmyRecruitedEvent final {
    ArmyId army_id;
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int64_t cost{};
};

struct ArmyMovedEvent final {
    ArmyId army_id;
    ProvinceId origin;
    ProvinceId destination;
    std::int32_t movement_cost{};
    std::int32_t remaining_points{};
};

struct MovementPointsGrantedEvent final {
    std::int32_t elapsed_months{};
    std::vector<ArmyMovementGrant> grants;
};

using GameEventPayload =
    std::variant<
        EconomyResolvedEvent,
        PopulationResolvedEvent,
        ArmyRecruitedEvent,
        ArmyMovedEvent,
        MovementPointsGrantedEvent,
        RoadBuiltEvent,
        TurnAdvancedEvent,
        WarDeclaredEvent
    >;

struct GameEvent final {
    std::uint64_t sequence{};
    GameEventType type{};
    GameEventPayload payload;
};

} // namespace province::core
