#pragma once

#include "province/core/army.hpp"
#include "province/core/country.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/province.hpp"
#include "province/core/road.hpp"

#include <cstddef>
#include <map>
#include <string>
#include <vector>

namespace province::core {

class GameState final {
public:
    explicit GameState(GameClock clock);

    void add_country(Country country);
    void add_province(Province province);

    [[nodiscard]] const GameClock& clock() const noexcept;
    [[nodiscard]] GameClock& clock() noexcept;
    [[nodiscard]] const Country* find_country(const CountryId& id) const noexcept;
    [[nodiscard]] Country* find_country(const CountryId& id) noexcept;
    [[nodiscard]] const Province* find_province(const ProvinceId& id) const noexcept;
    [[nodiscard]] Province* find_province(const ProvinceId& id) noexcept;
    [[nodiscard]] std::size_t country_count() const noexcept;
    [[nodiscard]] std::size_t province_count() const noexcept;
    [[nodiscard]] const std::map<CountryId, Country>& countries() const noexcept;
    [[nodiscard]] const std::map<ProvinceId, Province>& provinces() const noexcept;
    [[nodiscard]] bool are_adjacent(
        const ProvinceId& province_a,
        const ProvinceId& province_b
    ) const noexcept;
    [[nodiscard]] RoadLevel road_level(
        const ProvinceId& province_a,
        const ProvinceId& province_b
    ) const;
    void set_road_level(
        const ProvinceId& province_a,
        const ProvinceId& province_b,
        RoadLevel level
    );
    [[nodiscard]] const std::map<ProvinceConnectionKey, RoadLevel>& roads() const noexcept;
    [[nodiscard]] ArmyId create_army(
        const CountryId& owner_id,
        const ProvinceId& province_id,
        std::int64_t manpower
    );
    [[nodiscard]] const Army* find_army(const ArmyId& id) const noexcept;
    [[nodiscard]] Army* find_army(const ArmyId& id) noexcept;
    [[nodiscard]] const std::map<ArmyId, Army>& armies() const noexcept;
    [[nodiscard]] std::size_t army_count() const noexcept;
    [[nodiscard]] std::vector<std::string> validate() const;

private:
    GameClock clock_;
    std::map<CountryId, Country> countries_;
    std::map<ProvinceId, Province> provinces_;
    std::map<ProvinceConnectionKey, RoadLevel> roads_;
    std::map<ArmyId, Army> armies_;
    std::uint64_t next_army_sequence_{1};
};

} // namespace province::core
