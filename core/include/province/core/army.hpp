#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace province::core {

struct Army final {
    ArmyId id;
    CountryId owner_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int32_t movement_points{};
    std::optional<ProvinceId> advance_target;
    bool advance_enabled{true};
    std::string advance_strategy{"max"};
};

} // namespace province::core
