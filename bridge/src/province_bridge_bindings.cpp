#include "province_bridge.hpp"

#include <godot_cpp/core/class_db.hpp>

namespace province::bridge {

void ProvinceBridge::_bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("get_core_version"), &ProvinceBridge::get_core_version);
    godot::ClassDB::bind_method(godot::D_METHOD("advance_date", "year", "month", "months"), &ProvinceBridge::advance_date);
    godot::ClassDB::bind_method(godot::D_METHOD("load_scenario", "data_directory", "initial_year", "initial_month"), &ProvinceBridge::load_scenario);
    godot::ClassDB::bind_method(godot::D_METHOD("has_scenario"), &ProvinceBridge::has_scenario);
    godot::ClassDB::bind_method(godot::D_METHOD("get_last_error"), &ProvinceBridge::get_last_error);
    godot::ClassDB::bind_method(godot::D_METHOD("get_country_summaries"), &ProvinceBridge::get_country_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("get_province_summaries"), &ProvinceBridge::get_province_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("get_current_date"), &ProvinceBridge::get_current_date);
    godot::ClassDB::bind_method(godot::D_METHOD("advance_turn", "months"), &ProvinceBridge::advance_turn);
    godot::ClassDB::bind_method(godot::D_METHOD("build_road", "country_id", "province_a", "province_b"), &ProvinceBridge::build_road);
    godot::ClassDB::bind_method(godot::D_METHOD("get_road_summaries"), &ProvinceBridge::get_road_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("recruit_army", "country_id", "province_id", "manpower"), &ProvinceBridge::recruit_army);
    godot::ClassDB::bind_method(godot::D_METHOD("get_army_summaries"), &ProvinceBridge::get_army_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("move_army", "army_id", "destination"), &ProvinceBridge::move_army);
    godot::ClassDB::bind_method(godot::D_METHOD("auto_advance_army", "army_id"), &ProvinceBridge::auto_advance_army);
    godot::ClassDB::bind_method(godot::D_METHOD("auto_advance_army_to", "army_id", "target"), &ProvinceBridge::auto_advance_army_to);
    godot::ClassDB::bind_method(godot::D_METHOD("get_auto_advance_path", "army_id", "target"), &ProvinceBridge::get_auto_advance_path);
    godot::ClassDB::bind_method(godot::D_METHOD("get_auto_advance_path_for_months", "army_id", "target", "months"), &ProvinceBridge::get_auto_advance_path_for_months);
    godot::ClassDB::bind_method(godot::D_METHOD("set_army_advance_target", "army_id", "target"), &ProvinceBridge::set_army_advance_target);
    godot::ClassDB::bind_method(godot::D_METHOD("clear_army_advance_target", "army_id"), &ProvinceBridge::clear_army_advance_target);
    godot::ClassDB::bind_method(godot::D_METHOD("set_army_advance_enabled", "army_id", "enabled"), &ProvinceBridge::set_army_advance_enabled);
    godot::ClassDB::bind_method(godot::D_METHOD("set_army_advance_strategy", "army_id", "strategy"), &ProvinceBridge::set_army_advance_strategy);
    godot::ClassDB::bind_method(godot::D_METHOD("declare_war", "aggressor_id", "defender_id"), &ProvinceBridge::declare_war);
    godot::ClassDB::bind_method(godot::D_METHOD("get_diplomatic_relations"), &ProvinceBridge::get_diplomatic_relations);
    godot::ClassDB::bind_method(godot::D_METHOD("make_peace", "country_a", "country_b", "annex_occupied_provinces"), &ProvinceBridge::make_peace);
    godot::ClassDB::bind_method(godot::D_METHOD("set_ai_enabled", "enabled", "human_country_id"), &ProvinceBridge::set_ai_enabled);
    godot::ClassDB::bind_method(godot::D_METHOD("is_ai_enabled"), &ProvinceBridge::is_ai_enabled);
    godot::ClassDB::bind_method(godot::D_METHOD("get_technology_summaries"), &ProvinceBridge::get_technology_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("research_technology", "country_id", "track"), &ProvinceBridge::research_technology);
    godot::ClassDB::bind_method(godot::D_METHOD("save_game", "path"), &ProvinceBridge::save_game);
    godot::ClassDB::bind_method(godot::D_METHOD("load_game", "path"), &ProvinceBridge::load_game);
    godot::ClassDB::bind_method(godot::D_METHOD("get_game_status", "player_country_id"), &ProvinceBridge::get_game_status);
    godot::ClassDB::bind_method(godot::D_METHOD("get_war_summaries"), &ProvinceBridge::get_war_summaries);
    godot::ClassDB::bind_method(godot::D_METHOD("get_frontline_edges"), &ProvinceBridge::get_frontline_edges);
}

} // namespace province::bridge
