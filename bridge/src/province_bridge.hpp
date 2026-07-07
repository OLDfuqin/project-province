#pragma once

#include "province/core/game_state.hpp"
#include "province/core/command_processor.hpp"

#include <cstdint>
#include <optional>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace province::bridge {

class ProvinceBridge final : public godot::Node {
    GDCLASS(ProvinceBridge, godot::Node)

public:
    [[nodiscard]] godot::String get_core_version() const;
    [[nodiscard]] godot::Dictionary advance_date(
        std::int32_t year,
        std::int32_t month,
        std::int32_t months
    ) const;
    [[nodiscard]] bool load_scenario(
        const godot::String& data_directory,
        std::int32_t initial_year,
        std::int32_t initial_month
    );
    [[nodiscard]] bool has_scenario() const noexcept;
    [[nodiscard]] godot::String get_last_error() const;
    [[nodiscard]] godot::Array get_country_summaries() const;
    [[nodiscard]] godot::Array get_province_summaries() const;
    [[nodiscard]] godot::Dictionary get_current_date() const;
    [[nodiscard]] godot::Dictionary advance_turn(std::int32_t months);
    [[nodiscard]] godot::Dictionary build_road(
        const godot::String& country_id,
        const godot::String& province_a,
        const godot::String& province_b
    );
    [[nodiscard]] godot::Array get_road_summaries() const;

protected:
    static void _bind_methods();

private:
    std::optional<province::core::GameState> state_;
    province::core::CommandProcessor command_processor_;
    godot::String last_error_;
};

} // namespace province::bridge
