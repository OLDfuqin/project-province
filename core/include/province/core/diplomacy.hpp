#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <utility>

namespace province::core {

enum class DiplomaticStatus : std::uint8_t {
    peace,
    war,
};

class CountryRelationKey final {
public:
    CountryRelationKey(CountryId country_a, CountryId country_b)
        : countries_{country_b < country_a
              ? std::pair{std::move(country_b), std::move(country_a)}
              : std::pair{std::move(country_a), std::move(country_b)}} {}

    [[nodiscard]] const CountryId& first() const noexcept { return countries_.first; }
    [[nodiscard]] const CountryId& second() const noexcept { return countries_.second; }

    auto operator<=>(const CountryRelationKey&) const = default;

private:
    std::pair<CountryId, CountryId> countries_;
};

} // namespace province::core
