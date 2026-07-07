#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace province::core {

struct ArmyRecruitResult final {
    bool accepted{};
    std::string error;
    std::int64_t cost{};
    std::optional<ArmyId> army_id;
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
};

} // namespace province::core

