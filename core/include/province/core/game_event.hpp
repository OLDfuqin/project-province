#pragma once

#include "province/core/army.hpp"
#include "province/core/battle_system.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/game_order.hpp"
#include "province/core/maintenance_system.hpp"
#include "province/core/population_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/peace_system.hpp"
#include "province/core/road.hpp"
#include "province/core/technology_system.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace province::core {

enum class GameEventType : std::uint8_t {
    fiscal_income_resolved,
    maintenance_resolved,
    population_resolved,
    army_recruited,
    army_renamed,
    armies_merged,
    army_moved,
    battle_resolved,
    movement_points_granted,
    road_built,
    war_declared,
    peace_made,
    technology_researched,
    order_created,
    order_cancelled,
    turn_advanced,
};

struct OrderCreatedEvent final {
    OrderId order_id;
};

struct OrderCancelledEvent final {
    OrderId order_id;
    CountryId country_id;
    std::optional<ArmyId> army_id;
    std::int64_t refunded_cost{};
    std::int32_t refunded_movement_half{};
    std::string reason;
};

struct WarDeclaredEvent final {
    std::optional<OrderId> order_id;
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

struct FiscalIncomeResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<CountryFiscalIncome> fiscal_incomes;
};

struct MaintenanceResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<CountryMaintenanceCharge> charges;
};

struct PopulationResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<ProvincePopulationChange> changes;
};

struct RoadBuiltEvent final {
    OrderId order_id;
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
    RoadLevel level{RoadLevel::none};
    std::int64_t cost{};
};

struct ArmyRecruitedEvent final {
    OrderId order_id;
    ArmyId army_id;
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int64_t cost{};
};

struct ArmyRenamedEvent final {
    ArmyId army_id;
    CountryId country_id;
    std::int64_t previous_formation_number{};
    std::int64_t current_formation_number{};
};

struct ArmiesMergedEvent final {
    CountryId country_id;
    ProvinceId province_id;
    ArmyId primary_army_id;
    std::vector<ArmyId> merged_army_ids;
    std::int64_t previous_manpower{};
    std::int64_t current_manpower{};
    std::int32_t current_movement_points{};
    std::int64_t formation_number{};
    std::string display_name;
    bool automatic{};
};

struct ArmyMovedEvent final {
    OrderId order_id;
    ArmyId army_id;
    ProvinceId origin;
    ProvinceId destination;
    std::int32_t movement_cost_half{};
    std::int32_t remaining_movement_half{};
    bool converted_from_attack{};
};

struct BattleResolvedEvent final {
    std::vector<OrderId> order_ids;
    BattleResolution battle;
};

struct TechnologyResearchedEvent final {
    OrderId order_id;
    TechnologyResearchResult result;
};

struct MovementPointsGrantedEvent final {
    std::int32_t elapsed_months{};
    std::vector<ArmyMovementGrant> grants;
};

using GameEventPayload =
    std::variant<
        FiscalIncomeResolvedEvent,
        MaintenanceResolvedEvent,
        PopulationResolvedEvent,
        ArmyRecruitedEvent,
        ArmyRenamedEvent,
        ArmiesMergedEvent,
        ArmyMovedEvent,
        BattleResolvedEvent,
        MovementPointsGrantedEvent,
        RoadBuiltEvent,
        TurnAdvancedEvent,
        WarDeclaredEvent,
        PeaceSettlementResult,
        TechnologyResearchedEvent,
        OrderCreatedEvent,
        OrderCancelledEvent
    >;

struct GameEvent final {
    std::uint64_t sequence{};
    GameEventType type{};
    GameEventPayload payload;
};

} // namespace province::core
