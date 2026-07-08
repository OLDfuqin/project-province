#pragma once

#include "province/core/game_state.hpp"
#include "province/core/technology.hpp"

#include <cstdint>
#include <string>

namespace province::core {

struct TechnologyResearchResult final {
    bool accepted{};
    std::string error;
    CountryId country_id;
    TechnologyTrack track{TechnologyTrack::economy};
    std::int32_t previous_level{};
    std::int32_t current_level{};
    std::int64_t cost{};
};

class TechnologySystem final {
public:
    static constexpr std::int32_t maximum_level = 3;
    static constexpr std::int64_t base_research_cost = 1'000;

    [[nodiscard]] static std::int64_t research_cost(std::int32_t current_level) noexcept;
    [[nodiscard]] TechnologyResearchResult research(
        GameState& state,
        const CountryId& country_id,
        TechnologyTrack track
    ) const;
};

} // namespace province::core
