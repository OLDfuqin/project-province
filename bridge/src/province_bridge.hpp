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
    [[nodiscard]] godot::Dictionary recruit_army(
        const godot::String& country_id,
        const godot::String& province_id,
        std::int64_t manpower
    );
    [[nodiscard]] godot::Array get_army_summaries() const;
    [[nodiscard]] godot::Dictionary move_army(
        const godot::String& army_id,
        const godot::String& destination
    );
    [[nodiscard]] godot::Dictionary auto_advance_army(const godot::String& army_id);
    [[nodiscard]] godot::Dictionary auto_advance_army_to(
        const godot::String& army_id,
        const godot::String& target
    );
    [[nodiscard]] godot::Dictionary get_auto_advance_path(
        const godot::String& army_id,
        const godot::String& target
    ) const;
    [[nodiscard]] godot::Dictionary declare_war(
        const godot::String& aggressor_id,
        const godot::String& defender_id
    );
    [[nodiscard]] godot::Array get_diplomatic_relations() const;
    [[nodiscard]] godot::Dictionary make_peace(
        const godot::String& country_a,
        const godot::String& country_b,
        bool annex_occupied_provinces
    );
    void set_ai_enabled(bool enabled, const godot::String& human_country_id);
    [[nodiscard]] bool is_ai_enabled() const noexcept;
    [[nodiscard]] godot::Array get_technology_summaries() const;
    [[nodiscard]] godot::Dictionary research_technology(
        const godot::String& country_id,
        const godot::String& track
    );
    [[nodiscard]] godot::Dictionary save_game(const godot::String& path) const;
    [[nodiscard]] godot::Dictionary load_game(const godot::String& path);
    [[nodiscard]] godot::Dictionary get_game_status(const godot::String& player_country_id) const;
    [[nodiscard]] godot::Array get_war_summaries() const;
    [[nodiscard]] godot::Array get_frontline_edges() const;

protected:
    static void _bind_methods();

private:
    std::optional<province::core::GameState> state_;
    province::core::CommandProcessor command_processor_;
    godot::String last_error_;
};

} // namespace province::bridge
