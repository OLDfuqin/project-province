#pragma once

#include "province/core/stable_id.hpp"
#include "province/core/terrain.hpp"

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
    std::int64_t population_growth_remainder{};
    TerrainType terrain{TerrainType::plains};
};

} // namespace province::core
