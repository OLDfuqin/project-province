#include "province_bridge.hpp"

#include "province/core/game_clock.hpp"
#include "province/core/version.hpp"

#include <godot_cpp/core/class_db.hpp>

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

void ProvinceBridge::_bind_methods() {
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_core_version"),
        &ProvinceBridge::get_core_version
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("advance_date", "year", "month", "months"),
        &ProvinceBridge::advance_date
    );
}

} // namespace province::bridge

