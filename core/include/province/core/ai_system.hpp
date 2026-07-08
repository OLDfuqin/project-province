#pragma once

#include "province/core/game_command.hpp"
#include "province/core/game_state.hpp"

#include <vector>

namespace province::core {

struct AiDecision final {
    CountryId country_id;
    GameCommand command;
};

class AiSystem final {
public:
    [[nodiscard]] std::vector<AiDecision> plan_month(
        const GameState& state,
        const CountryId& human_country_id
    ) const;

private:
    static constexpr std::int64_t recruitment_batch = 500;
    static constexpr std::int64_t desired_manpower = 1'500;
    static constexpr std::int64_t war_readiness_manpower = 1'000;
};

} // namespace province::core
