#include "province/core/ai_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/technology_system.hpp"

#include <array>
#include <limits>
#include <map>
#include <optional>
#include <queue>

namespace province::core {
namespace {

std::int32_t connection_cost(
    const GameState& state,
    const ProvinceId& origin,
    const ProvinceId& destination
) {
    return state.road_level(origin, destination) == RoadLevel::paved
        ? MovementSystem::paved_road_cost
        : terrain_movement_cost(state.find_province(destination)->terrain);
}

std::optional<ProvinceId> choose_wartime_step(
    const GameState& state,
    const Army& army
) {
    const Province* origin = state.find_province(army.province_id);
    if (origin == nullptr) {
        return std::nullopt;
    }
    using QueueItem = std::pair<std::int32_t, ProvinceId>;
    struct Compare final {
        bool operator()(const QueueItem& left, const QueueItem& right) const {
            return left.first > right.first;
        }
    };
    std::map<ProvinceId, std::int32_t> distance;
    std::map<ProvinceId, ProvinceId> previous;
    std::priority_queue<QueueItem, std::vector<QueueItem>, Compare> frontier;
    distance.emplace(army.province_id, 0);
    frontier.push({0, army.province_id});

    while (!frontier.empty()) {
        const auto [current_distance, current_id] = frontier.top();
        frontier.pop();
        if (current_distance != distance[current_id]) {
            continue;
        }
        const Province* current = state.find_province(current_id);
        if (current == nullptr) {
            continue;
        }
        const CountryId current_controller = state.controller_of(current_id);
        if (current_id != army.province_id && current_controller != army.owner_id) {
            continue;
        }
        for (const ProvinceId& neighbor_id : current->neighbors) {
            const CountryId neighbor_controller = state.controller_of(neighbor_id);
            if (neighbor_controller != army.owner_id &&
                !state.are_at_war(army.owner_id, neighbor_controller)) {
                continue;
            }
            const std::int32_t candidate = current_distance +
                connection_cost(state, current_id, neighbor_id);
            const auto existing = distance.find(neighbor_id);
            if (existing == distance.end() || candidate < existing->second) {
                distance.insert_or_assign(neighbor_id, candidate);
                previous.insert_or_assign(neighbor_id, current_id);
                frontier.push({candidate, neighbor_id});
            }
        }
    }

    std::optional<ProvinceId> target;
    std::int32_t best_distance = std::numeric_limits<std::int32_t>::max();
    for (const auto& [province_id, province] : state.provinces()) {
        static_cast<void>(province);
        const CountryId controller = state.controller_of(province_id);
        const auto found = distance.find(province_id);
        if (controller != army.owner_id && state.are_at_war(army.owner_id, controller) &&
            found != distance.end() && found->second < best_distance) {
            target = province_id;
            best_distance = found->second;
        }
    }
    if (!target.has_value()) {
        return std::nullopt;
    }
    ProvinceId step = *target;
    while (previous.contains(step) && previous.at(step) != army.province_id) {
        step = previous.at(step);
    }
    return step == army.province_id ? std::nullopt : std::optional<ProvinceId>{step};
}

} // namespace

std::vector<AiDecision> AiSystem::plan_month(
    const GameState& state,
    const CountryId& human_country_id
) const {
    std::vector<AiDecision> decisions;
    std::map<CountryId, std::int64_t> military_strength;
    for (const auto& [country_id, country] : state.countries()) {
        static_cast<void>(country);
        military_strength.emplace(country_id, 0);
    }
    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army_id);
        military_strength[army.owner_id] += army.manpower;
    }

    for (const auto& [country_id, country] : state.countries()) {
        if (country_id == human_country_id) {
            continue;
        }

        if (military_strength[country_id] < desired_manpower &&
            country.treasury >= recruitment_batch) {
            for (const auto& [province_id, province] : state.provinces()) {
                if (state.controller_of(province_id) == country_id &&
                    province.soldier_population >= recruitment_batch) {
                    decisions.push_back(AiDecision{
                        country_id,
                        RecruitArmyCommand{country_id, province_id, recruitment_batch},
                    });
                    break;
                }
            }
        }

        if (military_strength[country_id] >= desired_manpower) {
            const CountryTechnology* technology = state.find_technology(country_id);
            if (technology != nullptr) {
                constexpr std::array tracks{
                    TechnologyTrack::economy,
                    TechnologyTrack::military,
                    TechnologyTrack::roads,
                };
                TechnologyTrack selected = tracks.front();
                for (const TechnologyTrack track : tracks) {
                    if (technology->level(track) < technology->level(selected)) {
                        selected = track;
                    }
                }
                const std::int32_t level = technology->level(selected);
                if (level < TechnologySystem::maximum_level &&
                    country.treasury >= TechnologySystem::research_cost(level)) {
                    decisions.push_back(AiDecision{
                        country_id,
                        ResearchTechnologyCommand{country_id, selected},
                    });
                }
            }
        }

        if (military_strength[country_id] >= war_readiness_manpower) {
            std::optional<CountryId> target;
            for (const auto& [province_id, province] : state.provinces()) {
                if (state.controller_of(province_id) != country_id) {
                    continue;
                }
                for (const ProvinceId& neighbor_id : province.neighbors) {
                    const CountryId neighbor_controller = state.controller_of(neighbor_id);
                    if (neighbor_controller != country_id &&
                        !state.are_at_war(country_id, neighbor_controller) &&
                        military_strength[country_id] >= military_strength[neighbor_controller]) {
                        target = neighbor_controller;
                        break;
                    }
                }
                if (target.has_value()) {
                    break;
                }
            }
            if (target.has_value()) {
                decisions.push_back(AiDecision{
                    country_id,
                    DeclareWarCommand{country_id, *target},
                });
            }
        }

        for (const auto& [army_id, army] : state.armies()) {
            if (army.owner_id != country_id) {
                continue;
            }
            const Province* province = state.find_province(army.province_id);
            if (province == nullptr) {
                continue;
            }
            const std::optional<ProvinceId> next_step = choose_wartime_step(state, army);
            if (next_step.has_value()) {
                const std::int32_t cost = connection_cost(state, army.province_id, *next_step);
                if (army.movement_points >= cost) {
                    decisions.push_back(AiDecision{
                        country_id,
                        MoveArmyCommand{army_id, *next_step},
                    });
                }
            }
        }
    }
    return decisions;
}

} // namespace province::core
