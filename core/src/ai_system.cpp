#include "province/core/ai_system.hpp"
#include "province/core/movement_system.hpp"

#include <map>
#include <optional>

namespace province::core {

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
            for (const ProvinceId& neighbor_id : province->neighbors) {
                const CountryId neighbor_controller = state.controller_of(neighbor_id);
                if (neighbor_controller == country_id ||
                    !state.are_at_war(country_id, neighbor_controller)) {
                    continue;
                }
                const std::int32_t cost =
                    state.road_level(army.province_id, neighbor_id) == RoadLevel::paved
                        ? MovementSystem::paved_road_cost
                        : MovementSystem::normal_connection_cost;
                if (army.movement_points >= cost) {
                    decisions.push_back(AiDecision{
                        country_id,
                        MoveArmyCommand{army_id, neighbor_id},
                    });
                }
                break;
            }
        }
    }
    return decisions;
}

} // namespace province::core
