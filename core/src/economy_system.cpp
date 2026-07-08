#include "province/core/economy_system.hpp"

#include <limits>
#include <map>
#include <stdexcept>

namespace province::core {

MonthlyEconomyReport EconomySystem::resolve_month(GameState& state) const {
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
        const CountryTechnology* technology = state.find_technology(controller);
        if (technology == nullptr) {
            throw std::logic_error{"cannot resolve economy without country technology"};
        }
        const std::int64_t province_income =
            province.economy * (100 + 10 * technology->economy_level) / 100;
        if (province_income > std::numeric_limits<std::int64_t>::max() - income->second) {
            throw std::overflow_error{"monthly country income overflow"};
        }
        income->second += province_income;
    }

    MonthlyEconomyReport report;
    report.incomes.reserve(income_by_country.size());
    for (const auto& [country_id, amount] : income_by_country) {
        Country* country = state.find_country(country_id);
        if (country == nullptr) {
            throw std::logic_error{"country disappeared during economy resolution"};
        }
        if (amount > std::numeric_limits<std::int64_t>::max() - country->treasury) {
            throw std::overflow_error{"country treasury overflow"};
        }
        country->treasury += amount;
        report.incomes.push_back(CountryIncome{country_id, amount});
    }
    return report;
}

} // namespace province::core
