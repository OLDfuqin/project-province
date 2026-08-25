#include "province/core/maintenance_system.hpp"

#include <limits>
#include <map>
#include <stdexcept>

namespace province::core {

MonthlyMaintenanceReport MaintenanceSystem::resolve_month(GameState& state) const {
    std::map<CountryId, std::int64_t> manpower_by_country;
    for (const auto& [country_id, country] : state.countries()) {
        if (!country.hidden) {
            manpower_by_country.emplace(country_id, 0);
        }
    }

    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army_id);
        const Country* country = state.find_country(army.owner_id);
        if (country == nullptr) {
            throw std::logic_error{"cannot resolve maintenance for army with unknown owner"};
        }
        if (country->hidden) continue;
        auto total = manpower_by_country.find(army.owner_id);
        if (total == manpower_by_country.end()) {
            throw std::logic_error{"normal army owner was omitted from maintenance"};
        }
        if (army.manpower > std::numeric_limits<std::int64_t>::max() - total->second) {
            throw std::overflow_error{"monthly army maintenance overflow"};
        }
        total->second += army.manpower;
    }

    MonthlyMaintenanceReport report;
    report.charges.reserve(manpower_by_country.size());
    for (const auto& [country_id, manpower] : manpower_by_country) {
        Country* country = state.find_country(country_id);
        if (country == nullptr) {
            throw std::logic_error{"country disappeared during maintenance resolution"};
        }
        const std::int64_t charge = manpower / 2;
        if (country->treasury < std::numeric_limits<std::int64_t>::min() + charge) {
            throw std::overflow_error{"country treasury underflow during maintenance"};
        }
        country->treasury -= charge;
        report.charges.push_back(CountryMaintenanceCharge{country_id, charge});
    }
    return report;
}

} // namespace province::core
