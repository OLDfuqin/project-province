#pragma once

#include "province/core/stable_id.hpp"

#include <compare>
#include <cstdint>
#include <utility>

namespace province::core {

enum class RoadLevel : std::uint8_t {
    none,
    paved,
};

class ProvinceConnectionKey final {
public:
    ProvinceConnectionKey(ProvinceId province_a, ProvinceId province_b);

    [[nodiscard]] const ProvinceId& first() const noexcept;
    [[nodiscard]] const ProvinceId& second() const noexcept;

    auto operator<=>(const ProvinceConnectionKey&) const = default;

private:
    ProvinceId first_;
    ProvinceId second_;
};

} // namespace province::core

