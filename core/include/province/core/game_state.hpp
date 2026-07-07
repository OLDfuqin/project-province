#pragma once

#include "province/core/country.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/province.hpp"

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
    [[nodiscard]] const Province* find_province(const ProvinceId& id) const noexcept;
    [[nodiscard]] std::size_t country_count() const noexcept;
    [[nodiscard]] std::size_t province_count() const noexcept;
    [[nodiscard]] std::vector<std::string> validate() const;

private:
    GameClock clock_;
    std::map<CountryId, Country> countries_;
    std::map<ProvinceId, Province> provinces_;
};

} // namespace province::core

