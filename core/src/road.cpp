#include "province/core/road.hpp"

#include <stdexcept>

namespace province::core {

ProvinceConnectionKey::ProvinceConnectionKey(
    ProvinceId province_a,
    ProvinceId province_b
) : first_{std::move(province_a)}, second_{std::move(province_b)} {
    if (first_ == second_) {
        throw std::invalid_argument{"a province connection requires two distinct provinces"};
    }
    if (second_ < first_) {
        std::swap(first_, second_);
    }
}

const ProvinceId& ProvinceConnectionKey::first() const noexcept {
    return first_;
}

const ProvinceId& ProvinceConnectionKey::second() const noexcept {
    return second_;
}

} // namespace province::core

