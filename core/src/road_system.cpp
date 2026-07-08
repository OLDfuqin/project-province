#include "province/core/road_system.hpp"

namespace province::core {

RoadBuildResult RoadSystem::build_paved_road(
    GameState& state,
    const CountryId& country_id,
    const ProvinceId& province_a,
    const ProvinceId& province_b
) const {
    Country* country = state.find_country(country_id);
    if (country == nullptr) {
        return {false, "road builder country does not exist", 0};
    }

    const Province* first = state.find_province(province_a);
    const Province* second = state.find_province(province_b);
    if (first == nullptr || second == nullptr) {
        return {false, "both road endpoint provinces must exist", 0};
    }
    if (!state.are_adjacent(province_a, province_b)) {
        return {false, "road endpoint provinces are not adjacent", 0};
    }
    if (state.controller_of(province_a) != country_id ||
        state.controller_of(province_b) != country_id) {
        return {false, "road endpoint provinces must be controlled by the paying country", 0};
    }
    if (state.road_level(province_a, province_b) != RoadLevel::none) {
        return {false, "a paved road already exists on this connection", 0};
    }
    const CountryTechnology* technology = state.find_technology(country_id);
    if (technology == nullptr) {
        return {false, "road builder has no technology state", 0};
    }
    const std::int64_t cost =
        paved_road_cost - 100 * technology->roads_level;
    if (country->treasury < cost) {
        return {false, "country treasury is insufficient to build the road", 0};
    }

    country->treasury -= cost;
    state.set_road_level(province_a, province_b, RoadLevel::paved);
    return {true, {}, cost};
}

} // namespace province::core
