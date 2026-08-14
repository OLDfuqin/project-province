#pragma once

#include "province/core/army.hpp"
#include "province/core/country.hpp"
#include "province/core/diplomacy.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/province.hpp"
#include "province/core/road.hpp"
#include "province/core/technology.hpp"

#include <cstddef>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace province::core {

class SaveGameSerializer;

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
    [[nodiscard]] const CountryTechnology* find_technology(
        const CountryId& country_id
    ) const noexcept;
    [[nodiscard]] CountryTechnology* find_technology(
        const CountryId& country_id
    ) noexcept;
    [[nodiscard]] const std::map<CountryId, CountryTechnology>& technologies() const noexcept;
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
    [[nodiscard]] std::int64_t next_formation_number(
        const CountryId& owner_id
    ) const;
    [[nodiscard]] std::string army_display_name(const ArmyId& army_id) const;
    void remove_army(const ArmyId& id);
    [[nodiscard]] CountryId controller_of(const ProvinceId& province_id) const;
    void set_occupation(const ProvinceId& province_id, const CountryId& controller_id);
    void clear_occupation(const ProvinceId& province_id);
    void transfer_province_ownership(
        const ProvinceId& province_id,
        const CountryId& new_owner_id
    );
    [[nodiscard]] const std::map<ProvinceId, CountryId>& occupations() const noexcept;
    [[nodiscard]] DiplomaticStatus diplomatic_status(
        const CountryId& country_a,
        const CountryId& country_b
    ) const;
    [[nodiscard]] bool are_at_war(
        const CountryId& country_a,
        const CountryId& country_b
    ) const;
    void set_diplomatic_status(
        const CountryId& country_a,
        const CountryId& country_b,
        DiplomaticStatus status
    );
    [[nodiscard]] const std::map<CountryRelationKey, DiplomaticStatus>& relations() const noexcept;
    [[nodiscard]] std::vector<std::string> validate() const;

private:
    friend class SaveGameSerializer;
    GameClock clock_;
    std::map<CountryId, Country> countries_;
    std::map<CountryId, CountryTechnology> technologies_;
    std::map<ProvinceId, Province> provinces_;
    std::map<ProvinceConnectionKey, RoadLevel> roads_;
    std::map<ArmyId, Army> armies_;
    std::map<ProvinceId, CountryId> occupations_;
    std::map<CountryRelationKey, DiplomaticStatus> relations_;
    std::uint64_t next_army_sequence_{1};
};

} // namespace province::core
