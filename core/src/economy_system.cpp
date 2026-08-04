#include "province/core/economy_system.hpp"

#include <limits>
#include <map>
#include <stdexcept>

namespace province::core {

namespace {

std::int64_t scaled_floor(
    const std::int64_t value,
    const std::int64_t numerator,
    const std::int64_t denominator
) {
    const std::int64_t whole = value / denominator;
    const std::int64_t remainder = value % denominator;
    if (whole > std::numeric_limits<std::int64_t>::max() / numerator) {
        throw std::overflow_error{"scaled integer calculation overflow"};
    }
    const std::int64_t whole_result = whole * numerator;
    const std::int64_t fractional_result = remainder * numerator / denominator;
    if (fractional_result >
        std::numeric_limits<std::int64_t>::max() - whole_result) {
        throw std::overflow_error{"scaled integer calculation overflow"};
    }
    return whole_result + fractional_result;
}

std::int64_t terrain_fiscal_numerator(const TerrainType terrain) noexcept {
    switch (terrain) {
    case TerrainType::plains:
        return 100;
    case TerrainType::forest:
    case TerrainType::hills:
        return 90;
    case TerrainType::mountains:
        return 80;
    }
    return 100;
}

} // namespace

std::int64_t EconomySystem::province_economy(
    const GameState& state,
    const ProvinceId& province_id
) {
    const Province* province = state.find_province(province_id);
    if (province == nullptr) {
        throw std::invalid_argument{"cannot calculate economy for unknown province"};
    }
    const CountryId controller = state.controller_of(province_id);
    const CountryTechnology* technology = state.find_technology(controller);
    if (technology == nullptr) {
        throw std::logic_error{"cannot calculate economy without controller technology"};
    }
    return scaled_floor(
        province->population,
        100 + 10 * technology->economy_level,
        100
    );
}

std::int64_t EconomySystem::province_fiscal_income(
    const GameState& state,
    const ProvinceId& province_id
) {
    const Province* province = state.find_province(province_id);
    if (province == nullptr) {
        throw std::invalid_argument{"cannot calculate fiscal income for unknown province"};
    }
    return scaled_floor(
        province_economy(state, province_id),
        terrain_fiscal_numerator(province->terrain),
        10'000
    );
}

MonthlyFiscalReport EconomySystem::resolve_month(GameState& state) const {
    std::map<CountryId, std::int64_t> income_by_country;
    for (const auto& [country_id, country] : state.countries()) {
        static_cast<void>(country);
        income_by_country.emplace(country_id, 0);
    }

    for (const auto& [province_id, province] : state.provinces()) {
        const CountryId controller = state.controller_of(province_id);
        auto income = income_by_country.find(controller);
        if (income == income_by_country.end()) {
            throw std::logic_error{"cannot resolve economy for province with unknown owner"};
        }
        const std::int64_t province_income = province_fiscal_income(state, province_id);
        if (province_income > std::numeric_limits<std::int64_t>::max() - income->second) {
            throw std::overflow_error{"monthly country income overflow"};
        }
        income->second += province_income;
    }

    MonthlyFiscalReport report;
    report.fiscal_incomes.reserve(income_by_country.size());
    for (const auto& [country_id, amount] : income_by_country) {
        Country* country = state.find_country(country_id);
        if (country == nullptr) {
            throw std::logic_error{"country disappeared during economy resolution"};
        }
        if (amount > std::numeric_limits<std::int64_t>::max() - country->treasury) {
            throw std::overflow_error{"country treasury overflow"};
        }
        country->treasury += amount;
        report.fiscal_incomes.push_back(CountryFiscalIncome{country_id, amount});
    }
    return report;
}

} // namespace province::core
