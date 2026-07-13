#include "province/core/army_system.hpp"

#include <limits>

namespace province::core {

ArmyRecruitResult ArmySystem::recruit(
    GameState& state,
    const CountryId& country_id,
    const ProvinceId& province_id,
    const std::int64_t manpower
) const {
    if (manpower <= 0) {
        return {false, "recruitment manpower must be positive", 0, std::nullopt};
    }
    if (manpower > std::numeric_limits<std::int64_t>::max() /
            recruitment_cost_per_soldier) {
        return {false, "recruitment cost overflow", 0, std::nullopt};
    }

    Country* country = state.find_country(country_id);
    Province* province = state.find_province(province_id);
    if (country == nullptr) {
        return {false, "recruiting country does not exist", 0, std::nullopt};
    }
    if (province == nullptr) {
        return {false, "recruitment province does not exist", 0, std::nullopt};
    }
    if (state.controller_of(province_id) != country_id) {
        return {false, "recruitment province is not controlled by the country", 0, std::nullopt};
    }
    if (province->recruitable_population < manpower) {
        return {false, "province recruitable population is insufficient", 0, std::nullopt};
    }

    const std::int64_t cost = manpower * recruitment_cost_per_soldier;
    if (country->treasury < cost) {
        return {false, "country treasury is insufficient for recruitment", 0, std::nullopt};
    }

    country->treasury -= cost;
    province->recruitable_population -= manpower;
    const ArmyId army_id = state.create_army(country_id, province_id, manpower);
    return {true, {}, cost, army_id};
}

} // namespace province::core
