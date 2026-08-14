#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace province::core {

struct ArmyRecruitResult final {
    bool accepted{};
    std::string error;
    std::int64_t cost{};
    std::optional<ArmyId> army_id;
};

struct ArmyRenameResult final {
    bool accepted{};
    std::string error;
    CountryId country_id;
    std::int64_t previous_formation_number{};
    std::int64_t current_formation_number{};
};

struct ArmyMergeResult final {
    bool accepted{};
    std::string error;
    std::int64_t previous_manpower{};
    std::int64_t current_manpower{};
    std::int32_t current_movement_points{};
};

class ArmySystem final {
public:
    static constexpr std::int64_t recruitment_cost_per_soldier = 1;

    [[nodiscard]] ArmyRecruitResult recruit(
        GameState& state,
        const CountryId& country_id,
        const ProvinceId& province_id,
        std::int64_t manpower
    ) const;
    [[nodiscard]] ArmyRenameResult rename(
        GameState& state,
        const ArmyId& army_id,
        std::int64_t formation_number
    ) const;
    [[nodiscard]] ArmyMergeResult merge(
        GameState& state,
        const ArmyId& primary_army_id,
        const std::vector<ArmyId>& merged_army_ids
    ) const;
};

} // namespace province::core
