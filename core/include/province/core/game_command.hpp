#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <variant>

namespace province::core {

struct AdvanceTurnCommand final {
    std::int32_t months{};
};

struct BuildRoadCommand final {
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
};

struct RecruitArmyCommand final {
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
};

using GameCommand =
    std::variant<AdvanceTurnCommand, BuildRoadCommand, RecruitArmyCommand>;

} // namespace province::core
