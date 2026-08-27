#pragma once

#include "province/core/battle_system.hpp"
#include "province/core/game_state.hpp"
#include "province/core/road_system.hpp"
#include "province/core/technology_system.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace province::core {

struct ResolvedArmyMovement final {
    OrderId order_id;
    ArmyId army_id;
    ProvinceId origin;
    ProvinceId destination;
    std::int32_t movement_cost_half{};
    std::int32_t remaining_movement_half{};
    bool converted_from_attack{};
};

struct RefundedArmyAction final {
    OrderId order_id;
    CountryId country_id;
    ArmyId army_id;
    std::int32_t refunded_movement_half{};
    std::string reason;
};

struct MonthlyOrderMovementReport final {
    std::vector<ResolvedArmyMovement> movements;
    std::vector<RefundedArmyAction> refunds;
};

struct ResolvedOrderCombat final {
    std::vector<OrderId> order_ids;
    BattleResolution battle;
};

struct MonthlyOrderCombatReport final {
    std::vector<ResolvedOrderCombat> battles;
    std::vector<RefundedArmyAction> refunds;
};

struct ResolvedWarDeclaration final {
    OrderId order_id;
    CountryId aggressor_id;
    CountryId defender_id;
};

struct InvalidatedWarDeclaration final {
    OrderId order_id;
    CountryId country_id;
    std::string reason;
};

struct MonthlyOrderDiplomacyReport final {
    std::vector<ResolvedWarDeclaration> declarations;
    std::vector<InvalidatedWarDeclaration> invalidations;
};

struct CompletedRecruitmentOrder final {
    OrderId order_id;
    ArmyId army_id;
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int64_t paid_cost{};
};

struct CompletedRoadOrder final {
    OrderId order_id;
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
    std::int64_t paid_cost{};
};

struct CompletedResearchOrder final {
    OrderId order_id;
    TechnologyResearchResult result;
};

struct RefundedProjectOrder final {
    OrderId order_id;
    CountryId country_id;
    std::int64_t refunded_cost{};
    std::string reason;
};

struct MonthlyOrderProjectReport final {
    std::vector<CompletedRecruitmentOrder> recruitments;
    std::vector<CompletedRoadOrder> roads;
    std::vector<CompletedResearchOrder> research;
    std::vector<RefundedProjectOrder> refunds;
};

struct AutomaticArmyMerge final {
    CountryId country_id;
    ProvinceId province_id;
    ArmyId primary_army_id;
    std::vector<ArmyId> merged_army_ids;
    std::int64_t previous_manpower{};
    std::int64_t current_manpower{};
    std::int32_t current_movement_points{};
    std::int64_t formation_number{};
    std::string display_name;
};

struct MonthlyArmyConsolidationReport final {
    std::vector<AutomaticArmyMerge> merges;
};

class MonthlyOrderSystem final {
public:
    [[nodiscard]] MonthlyOrderDiplomacyReport resolve_diplomacy(
        GameState& state
    ) const;
    [[nodiscard]] MonthlyOrderMovementReport resolve_movement(GameState& state) const;
    [[nodiscard]] MonthlyOrderCombatReport resolve_combat(
        GameState& state,
        const BattleSystem& battle_system
    ) const;
    [[nodiscard]] MonthlyOrderProjectReport resolve_projects(GameState& state) const;
    [[nodiscard]] MonthlyArmyConsolidationReport consolidate_armies(
        GameState& state
    ) const;
};

} // namespace province::core
