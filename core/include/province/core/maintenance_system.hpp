#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <vector>

namespace province::core {

struct CountryMaintenanceCharge final {
    CountryId country_id;
    std::int64_t amount{};
};

struct MonthlyMaintenanceReport final {
    std::vector<CountryMaintenanceCharge> charges;
};

class MaintenanceSystem final {
public:
    [[nodiscard]] MonthlyMaintenanceReport resolve_month(GameState& state) const;
};

} // namespace province::core
