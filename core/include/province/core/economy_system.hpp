#pragma once

#include "province/core/game_state.hpp"
#include "province/core/stable_id.hpp"

#include <cstdint>
#include <vector>

namespace province::core {

struct CountryFiscalIncome final {
    CountryId country_id;
    std::int64_t amount{};
};

struct MonthlyFiscalReport final {
    std::vector<CountryFiscalIncome> fiscal_incomes;
};

class EconomySystem final {
public:
    [[nodiscard]] static std::int64_t province_economy(
        const GameState& state,
        const ProvinceId& province_id
    );
    [[nodiscard]] static std::int64_t province_fiscal_income(
        const GameState& state,
        const ProvinceId& province_id
    );
    [[nodiscard]] MonthlyFiscalReport resolve_month(GameState& state) const;
};

} // namespace province::core
