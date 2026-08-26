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
    if (country->hidden) {
        return {false, "hidden neutral country cannot research", country_id, track, 0, 0, 0};
    }
    const std::int32_t previous_level = technology->level(track);
    if (previous_level >= maximum_level(track)) {
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

TechnologyResearchResult TechnologySystem::complete_prepaid_research(
    GameState& state,
    const CountryId& country_id,
    const TechnologyTrack track,
    const std::int32_t previous_level,
    const std::int32_t target_level,
    const std::int64_t paid_cost
) const {
    Country* country = state.find_country(country_id);
    CountryTechnology* technology = state.find_technology(country_id);
    if (country == nullptr || technology == nullptr) {
        return {
            false,
            "researching country does not exist",
            country_id,
            track,
            previous_level,
            previous_level,
            0,
        };
    }
    if (country->hidden) {
        return {
            false,
            "hidden neutral country cannot research",
            country_id,
            track,
            previous_level,
            previous_level,
            0,
        };
    }
    if (paid_cost <= 0 || target_level != previous_level + 1 ||
        target_level > maximum_level(track) || technology->level(track) != previous_level) {
        return {
            false,
            "research order no longer matches the current technology level",
            country_id,
            track,
            technology->level(track),
            technology->level(track),
            0,
        };
    }

    technology->level(track) = target_level;
    return {
        true,
        {},
        country_id,
        track,
        previous_level,
        target_level,
        paid_cost,
    };
}

} // namespace province::core
