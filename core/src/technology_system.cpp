#include "province/core/technology_system.hpp"

namespace province::core {

std::int64_t TechnologySystem::research_cost(const std::int32_t current_level) noexcept {
    return base_research_cost * (static_cast<std::int64_t>(current_level) + 1);
}

TechnologyResearchResult TechnologySystem::research(
    GameState& state,
    const CountryId& country_id,
    const TechnologyTrack track
) const {
    Country* country = state.find_country(country_id);
    CountryTechnology* technology = state.find_technology(country_id);
    if (country == nullptr || technology == nullptr) {
        return {false, "researching country does not exist", country_id, track, 0, 0, 0};
    }
    const std::int32_t previous_level = technology->level(track);
    if (previous_level >= maximum_level) {
        return {
            false,
            "technology track is already at maximum level",
            country_id,
            track,
            previous_level,
            previous_level,
            0,
        };
    }
    const std::int64_t cost = research_cost(previous_level);
    if (country->treasury < cost) {
        return {
            false,
            "country treasury is insufficient for research",
            country_id,
            track,
            previous_level,
            previous_level,
            cost,
        };
    }
    country->treasury -= cost;
    technology->level(track) = previous_level + 1;
    return {
        true,
        {},
        country_id,
        track,
        previous_level,
        previous_level + 1,
        cost,
    };
}

} // namespace province::core
