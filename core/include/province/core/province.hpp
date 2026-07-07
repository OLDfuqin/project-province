#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace province::core {

struct Province final {
    ProvinceId id;
    std::string name;
    CountryId owner_id;
    std::int64_t population{};
    std::int64_t soldier_population{};
    std::int64_t economy{};
    std::vector<ProvinceId> neighbors;
};

} // namespace province::core

