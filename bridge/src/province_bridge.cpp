#include "province_bridge.hpp"

#include "province/core/game_clock.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/version.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <filesystem>
#include <string>

namespace province::bridge {

godot::String ProvinceBridge::get_core_version() const {
    const auto value = province::core::version();
    return godot::String{std::string{value}.c_str()};
}

godot::Dictionary ProvinceBridge::advance_date(
    const std::int32_t year,
    const std::int32_t month,
    const std::int32_t months
) const {
    province::core::GameClock clock{year, month};
    clock.advance_months(months);

    godot::Dictionary result;
    result["year"] = clock.year();
    result["month"] = clock.month();
    result["elapsed_months"] = clock.elapsed_months();
    return result;
}

bool ProvinceBridge::load_scenario(
    const godot::String& data_directory,
    const std::int32_t initial_year,
    const std::int32_t initial_month
) {
    try {
        const godot::CharString utf8_path = data_directory.utf8();
        state_.emplace(province::core::ScenarioLoader::load(
            std::filesystem::u8path(utf8_path.get_data()),
            province::core::GameClock{initial_year, initial_month}
        ));
        last_error_ = godot::String{};
        return true;
    } catch (const std::exception& error) {
        state_.reset();
        last_error_ = godot::String::utf8(error.what());
        return false;
    }
}

bool ProvinceBridge::has_scenario() const noexcept {
    return state_.has_value();
}

godot::String ProvinceBridge::get_last_error() const {
    return last_error_;
}

godot::Array ProvinceBridge::get_country_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }

    for (const auto& [country_id, country] : state_->countries()) {
        std::int64_t province_count = 0;
        for (const auto& [province_id, province] : state_->provinces()) {
            static_cast<void>(province_id);
            if (province.owner_id == country_id) {
                ++province_count;
            }
        }

        godot::Dictionary summary;
        summary["id"] = godot::String::utf8(country_id.value().c_str());
        summary["name"] = godot::String::utf8(country.name.c_str());
        summary["color_rgb"] = static_cast<std::int64_t>(country.color_rgb);
        summary["treasury"] = country.treasury;
        summary["province_count"] = province_count;
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Array ProvinceBridge::get_province_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }

    for (const auto& [province_id, province] : state_->provinces()) {
        godot::Dictionary summary;
        summary["id"] = godot::String::utf8(province_id.value().c_str());
        summary["name"] = godot::String::utf8(province.name.c_str());
        summary["owner_id"] = godot::String::utf8(province.owner_id.value().c_str());
        summary["population"] = province.population;
        summary["soldier_population"] = province.soldier_population;
        summary["economy"] = province.economy;
        summary["neighbor_count"] = static_cast<std::int64_t>(province.neighbors.size());
        summaries.push_back(summary);
    }
    return summaries;
}

void ProvinceBridge::_bind_methods() {
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_core_version"),
        &ProvinceBridge::get_core_version
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("advance_date", "year", "month", "months"),
        &ProvinceBridge::advance_date
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("load_scenario", "data_directory", "initial_year", "initial_month"),
        &ProvinceBridge::load_scenario
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("has_scenario"),
        &ProvinceBridge::has_scenario
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_last_error"),
        &ProvinceBridge::get_last_error
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_country_summaries"),
        &ProvinceBridge::get_country_summaries
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_province_summaries"),
        &ProvinceBridge::get_province_summaries
    );
}

} // namespace province::bridge
