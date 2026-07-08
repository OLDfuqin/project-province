#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <optional>

namespace province::core {

struct Army final {
    ArmyId id;
    CountryId owner_id;
    ProvinceId province_id;
    std::int64_t manpower{};
    std::int32_t movement_points{};
    std::optional<ProvinceId> advance_target;
};

} // namespace province::core
