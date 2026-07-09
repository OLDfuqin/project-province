#include "province_bridge.hpp"

#include "province/core/ai_system.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_status.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/save_game.hpp"
#include "province/core/version.hpp"

#include <godot_cpp/core/class_db.hpp>

#include <filesystem>
#include <string>
#include <vector>

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
        command_processor_ = province::core::CommandProcessor{};
        command_processor_.enable_ai(province::core::CountryId{"auroria"});
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
            static_cast<void>(province);
            if (state_->controller_of(province_id) == country_id) {
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
        const province::core::CountryId controller = state_->controller_of(province_id);
        summary["owner_id"] = godot::String::utf8(controller.value().c_str());
        summary["legal_owner_id"] = godot::String::utf8(province.owner_id.value().c_str());
        summary["occupied"] = controller != province.owner_id;
        summary["population"] = province.population;
        summary["soldier_population"] = province.soldier_population;
        summary["economy"] = province.economy;
        summary["terrain"] = province::core::terrain_name(province.terrain);
        summary["neighbor_count"] = static_cast<std::int64_t>(province.neighbors.size());
        godot::Array neighbors;
        for (const province::core::ProvinceId& neighbor_id : province.neighbors) {
            neighbors.push_back(godot::String::utf8(neighbor_id.value().c_str()));
        }
        summary["neighbors"] = neighbors;
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::get_current_date() const {
    godot::Dictionary date;
    if (!state_) {
        return date;
    }
    date["year"] = state_->clock().year();
    date["month"] = state_->clock().month();
    return date;
}

godot::Dictionary ProvinceBridge::advance_turn(const std::int32_t months) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }

    const province::core::CommandResult result = command_processor_.execute(
        *state_,
        province::core::AdvanceTurnCommand{months}
    );
    response["accepted"] = result.accepted;
    response["error"] = godot::String::utf8(result.error.c_str());
    response["year"] = state_->clock().year();
    response["month"] = state_->clock().month();

    godot::Array incomes;
    godot::Array population_changes;
    godot::Array turn_actions;
    for (const province::core::GameEvent& event : result.events) {
        if (event.type == province::core::GameEventType::economy_resolved) {
            const auto& economy = std::get<province::core::EconomyResolvedEvent>(event.payload);
            for (const province::core::CountryIncome& income : economy.incomes) {
                godot::Dictionary income_summary;
                income_summary["country_id"] =
                    godot::String::utf8(income.country_id.value().c_str());
                income_summary["amount"] = income.amount;
                incomes.push_back(income_summary);
            }
            response["economy_event_sequence"] = static_cast<std::int64_t>(event.sequence);
        } else if (event.type == province::core::GameEventType::population_resolved) {
            const auto& population =
                std::get<province::core::PopulationResolvedEvent>(event.payload);
            for (const province::core::ProvincePopulationChange& change : population.changes) {
                godot::Dictionary change_summary;
                change_summary["province_id"] =
                    godot::String::utf8(change.province_id.value().c_str());
                change_summary["growth"] = change.growth;
                change_summary["current_population"] = change.current_population;
                population_changes.push_back(change_summary);
            }
            response["population_event_sequence"] = static_cast<std::int64_t>(event.sequence);
        } else if (event.type == province::core::GameEventType::turn_advanced) {
            const auto& turn = std::get<province::core::TurnAdvancedEvent>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["event_type"] = "turn_advanced";
            response["elapsed_months"] = turn.elapsed_months;
            response["previous_year"] = turn.previous_year;
            response["previous_month"] = turn.previous_month;
        } else if (event.type != province::core::GameEventType::movement_points_granted) {
            godot::Dictionary action;
            action["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            if (event.type == province::core::GameEventType::army_recruited) {
                const auto& recruited =
                    std::get<province::core::ArmyRecruitedEvent>(event.payload);
                action["type"] = "army_recruited";
                action["country_id"] =
                    godot::String::utf8(recruited.country_id.value().c_str());
            } else if (event.type == province::core::GameEventType::war_declared) {
                const auto& war = std::get<province::core::WarDeclaredEvent>(event.payload);
                action["type"] = "war_declared";
                action["country_id"] =
                    godot::String::utf8(war.aggressor_id.value().c_str());
                action["target_id"] =
                    godot::String::utf8(war.defender_id.value().c_str());
            } else if (event.type == province::core::GameEventType::army_moved) {
                const auto& moved = std::get<province::core::ArmyMovedEvent>(event.payload);
                action["type"] = "army_moved";
                action["army_id"] = godot::String::utf8(moved.army_id.value().c_str());
                action["origin"] = godot::String::utf8(moved.origin.value().c_str());
                action["destination"] =
                    godot::String::utf8(moved.destination.value().c_str());
                action["movement_cost"] = moved.movement_cost;
                action["remaining_points"] = moved.remaining_points;
            } else if (event.type == province::core::GameEventType::battle_resolved) {
                const auto& battle =
                    std::get<province::core::BattleResolution>(event.payload);
                action["type"] = "battle_resolved";
                action["province_id"] =
                    godot::String::utf8(battle.province_id.value().c_str());
                action["battle_occurred"] = battle.occurred;
                action["attacker_won"] = battle.attacker_won;
                action["province_occupied"] = battle.province_occupied;
                std::int64_t casualties = 0;
                godot::Array outcomes;
                for (const province::core::ArmyBattleOutcome& outcome : battle.armies) {
                    casualties += outcome.casualties;
                    godot::Dictionary summary;
                    summary["army_id"] =
                        godot::String::utf8(outcome.army_id.value().c_str());
                    summary["casualties"] = outcome.casualties;
                    summary["remaining_manpower"] = outcome.remaining_manpower;
                    summary["destroyed"] = outcome.destroyed;
                    summary["retreat_province"] = outcome.retreat_province.has_value()
                        ? godot::String::utf8(outcome.retreat_province->value().c_str())
                        : godot::String{};
                    outcomes.push_back(summary);
                }
                action["casualties"] = casualties;
                action["battle_outcomes"] = outcomes;
            } else if (event.type == province::core::GameEventType::technology_researched) {
                const auto& research =
                    std::get<province::core::TechnologyResearchResult>(event.payload);
                action["type"] = "technology_researched";
                action["country_id"] =
                    godot::String::utf8(research.country_id.value().c_str());
            } else {
                action["type"] = "other";
            }
            turn_actions.push_back(action);
        }
    }
    response["incomes"] = incomes;
    response["population_changes"] = population_changes;
    response["turn_actions"] = turn_actions;
    response["ai_actions"] = turn_actions;
    return response;
}

void ProvinceBridge::set_ai_enabled(
    const bool enabled,
    const godot::String& human_country_id
) {
    if (!enabled) {
        command_processor_.disable_ai();
        return;
    }
    command_processor_.enable_ai(
        province::core::CountryId{human_country_id.utf8().get_data()}
    );
}

bool ProvinceBridge::is_ai_enabled() const noexcept {
    return command_processor_.ai_enabled();
}

godot::Array ProvinceBridge::get_technology_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }
    for (const auto& [country_id, technology] : state_->technologies()) {
        godot::Dictionary summary;
        summary["country_id"] = godot::String::utf8(country_id.value().c_str());
        summary["economy_level"] = technology.economy_level;
        summary["military_level"] = technology.military_level;
        summary["roads_level"] = technology.roads_level;
        summary["economy_cost"] = technology.economy_level <
                province::core::TechnologySystem::maximum_level
            ? province::core::TechnologySystem::research_cost(technology.economy_level)
            : 0;
        summary["military_cost"] = technology.military_level <
                province::core::TechnologySystem::maximum_level
            ? province::core::TechnologySystem::research_cost(technology.military_level)
            : 0;
        summary["roads_cost"] = technology.roads_level <
                province::core::TechnologySystem::maximum_level
            ? province::core::TechnologySystem::research_cost(technology.roads_level)
            : 0;
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::research_technology(
    const godot::String& country_id,
    const godot::String& track
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const std::string track_name = track.utf8().get_data();
        province::core::TechnologyTrack technology_track;
        if (track_name == "economy") {
            technology_track = province::core::TechnologyTrack::economy;
        } else if (track_name == "military") {
            technology_track = province::core::TechnologyTrack::military;
        } else if (track_name == "roads") {
            technology_track = province::core::TechnologyTrack::roads;
        } else {
            response["accepted"] = false;
            response["error"] = "technology track must be economy, military or roads";
            return response;
        }
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::ResearchTechnologyCommand{
                province::core::CountryId{country_id.utf8().get_data()},
                technology_track,
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const province::core::GameEvent& event = result.events.front();
            const auto& research =
                std::get<province::core::TechnologyResearchResult>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["previous_level"] = research.previous_level;
            response["current_level"] = research.current_level;
            response["cost"] = research.cost;
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::save_game(const godot::String& path) const {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const godot::CharString utf8_path = path.utf8();
        province::core::SaveGameSerializer::save(
            std::filesystem::u8path(utf8_path.get_data()),
            *state_,
            command_processor_.next_event_sequence(),
            command_processor_.human_country_id()
        );
        response["accepted"] = true;
        response["error"] = godot::String{};
        response["path"] = path;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::load_game(const godot::String& path) {
    godot::Dictionary response;
    try {
        const godot::CharString utf8_path = path.utf8();
        province::core::LoadedGame loaded = province::core::SaveGameSerializer::load(
            std::filesystem::u8path(utf8_path.get_data())
        );
        province::core::CommandProcessor restored_processor;
        restored_processor.set_next_event_sequence(loaded.next_event_sequence);
        if (loaded.human_country_id.has_value()) {
            restored_processor.enable_ai(*loaded.human_country_id);
        }
        state_ = std::move(loaded.state);
        command_processor_ = std::move(restored_processor);
        last_error_ = godot::String{};
        response["accepted"] = true;
        response["error"] = godot::String{};
        response["path"] = path;
        response["year"] = state_->clock().year();
        response["month"] = state_->clock().month();
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::get_game_status(
    const godot::String& player_country_id
) const {
    godot::Dictionary response;
    if (!state_) {
        response["has_scenario"] = false;
        return response;
    }
    const province::core::GameStatus status = province::core::GameStatusSystem{}.evaluate(
        *state_,
        province::core::CountryId{player_country_id.utf8().get_data()}
    );
    response["has_scenario"] = true;
    response["game_over"] = status.game_over;
    response["player_eliminated"] = status.player_eliminated;
    response["player_won"] = status.player_won;
    response["winner_id"] = status.winner_id.has_value()
        ? godot::String::utf8(status.winner_id->value().c_str())
        : godot::String{};
    godot::Array countries;
    for (const auto& [country_id, country_status] : status.countries) {
        godot::Dictionary summary;
        summary["country_id"] = godot::String::utf8(country_id.value().c_str());
        summary["controlled_provinces"] = country_status.controlled_provinces;
        summary["eliminated"] = country_status.eliminated;
        countries.push_back(summary);
    }
    response["countries"] = countries;
    return response;
}

godot::Array ProvinceBridge::get_war_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }
    for (const auto& [relation, status] : state_->relations()) {
        if (status != province::core::DiplomaticStatus::war) {
            continue;
        }
        const province::core::CountryId first = relation.first();
        const province::core::CountryId second = relation.second();
        std::int64_t first_manpower = 0;
        std::int64_t second_manpower = 0;
        for (const auto& [army_id, army] : state_->armies()) {
            static_cast<void>(army_id);
            if (army.owner_id == first) {
                first_manpower += army.manpower;
            } else if (army.owner_id == second) {
                second_manpower += army.manpower;
            }
        }
        std::int64_t first_occupied = 0;
        std::int64_t second_occupied = 0;
        std::int64_t front_edges = 0;
        for (const auto& [province_id, province] : state_->provinces()) {
            const province::core::CountryId controller = state_->controller_of(province_id);
            if (province.owner_id == first && controller == second) {
                ++second_occupied;
            } else if (province.owner_id == second && controller == first) {
                ++first_occupied;
            }
            for (const province::core::ProvinceId& neighbor_id : province.neighbors) {
                if (province_id < neighbor_id) {
                    const province::core::CountryId neighbor_controller =
                        state_->controller_of(neighbor_id);
                    const bool first_second_edge =
                        (controller == first && neighbor_controller == second) ||
                        (controller == second && neighbor_controller == first);
                    if (first_second_edge) {
                        ++front_edges;
                    }
                }
            }
        }
        godot::Dictionary summary;
        summary["country_a"] = godot::String::utf8(first.value().c_str());
        summary["country_b"] = godot::String::utf8(second.value().c_str());
        summary["country_a_manpower"] = first_manpower;
        summary["country_b_manpower"] = second_manpower;
        summary["country_a_occupied_provinces"] = first_occupied;
        summary["country_b_occupied_provinces"] = second_occupied;
        summary["front_edges"] = front_edges;
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Array ProvinceBridge::get_frontline_edges() const {
    godot::Array edges;
    if (!state_) {
        return edges;
    }
    for (const auto& [province_id, province] : state_->provinces()) {
        const province::core::CountryId controller = state_->controller_of(province_id);
        for (const province::core::ProvinceId& neighbor_id : province.neighbors) {
            if (neighbor_id < province_id) {
                continue;
            }
            const province::core::CountryId neighbor_controller = state_->controller_of(neighbor_id);
            if (controller != neighbor_controller &&
                state_->are_at_war(controller, neighbor_controller)) {
                godot::Dictionary edge;
                edge["province_a"] = godot::String::utf8(province_id.value().c_str());
                edge["province_b"] = godot::String::utf8(neighbor_id.value().c_str());
                edge["country_a"] = godot::String::utf8(controller.value().c_str());
                edge["country_b"] = godot::String::utf8(neighbor_controller.value().c_str());
                edges.push_back(edge);
            }
        }
    }
    return edges;
}

godot::Dictionary ProvinceBridge::build_road(
    const godot::String& country_id,
    const godot::String& province_a,
    const godot::String& province_b
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }

    try {
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::BuildRoadCommand{
                province::core::CountryId{country_id.utf8().get_data()},
                province::core::ProvinceId{province_a.utf8().get_data()},
                province::core::ProvinceId{province_b.utf8().get_data()},
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const province::core::GameEvent& event = result.events.front();
            const auto& road = std::get<province::core::RoadBuiltEvent>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["cost"] = road.cost;
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Array ProvinceBridge::get_road_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }
    for (const auto& [connection, level] : state_->roads()) {
        godot::Dictionary summary;
        summary["province_a"] = godot::String::utf8(connection.first().value().c_str());
        summary["province_b"] = godot::String::utf8(connection.second().value().c_str());
        summary["level"] = level == province::core::RoadLevel::paved ? "paved" : "none";
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::recruit_army(
    const godot::String& country_id,
    const godot::String& province_id,
    const std::int64_t manpower
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::RecruitArmyCommand{
                province::core::CountryId{country_id.utf8().get_data()},
                province::core::ProvinceId{province_id.utf8().get_data()},
                manpower,
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const province::core::GameEvent& event = result.events.front();
            const auto& recruited =
                std::get<province::core::ArmyRecruitedEvent>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["army_id"] = godot::String::utf8(recruited.army_id.value().c_str());
            response["cost"] = recruited.cost;
            response["manpower"] = recruited.manpower;
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Array ProvinceBridge::get_army_summaries() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }
    for (const auto& [army_id, army] : state_->armies()) {
        godot::Dictionary summary;
        summary["id"] = godot::String::utf8(army_id.value().c_str());
        summary["owner_id"] = godot::String::utf8(army.owner_id.value().c_str());
        summary["province_id"] = godot::String::utf8(army.province_id.value().c_str());
        summary["manpower"] = army.manpower;
        summary["movement_points"] = army.movement_points;
        summary["advance_target_id"] = army.advance_target.has_value()
            ? godot::String::utf8(army.advance_target->value().c_str())
            : godot::String{};
        summary["advance_enabled"] = army.advance_enabled;
        summary["advance_strategy"] = godot::String::utf8(army.advance_strategy.c_str());
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::move_army(
    const godot::String& army_id,
    const godot::String& destination
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::MoveArmyCommand{
                province::core::ArmyId{army_id.utf8().get_data()},
                province::core::ProvinceId{destination.utf8().get_data()},
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            for (const province::core::GameEvent& event : result.events) {
                if (event.type == province::core::GameEventType::army_moved) {
                    const auto& moved =
                        std::get<province::core::ArmyMovedEvent>(event.payload);
                    response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
                    response["movement_cost"] = moved.movement_cost;
                    response["remaining_points"] = moved.remaining_points;
                    response["origin"] = godot::String::utf8(moved.origin.value().c_str());
                    response["destination"] =
                        godot::String::utf8(moved.destination.value().c_str());
                } else if (event.type == province::core::GameEventType::battle_resolved) {
                    const auto& battle =
                        std::get<province::core::BattleResolution>(event.payload);
                    response["battle_event_sequence"] =
                        static_cast<std::int64_t>(event.sequence);
                    response["battle_occurred"] = battle.occurred;
                    response["attacker_won"] = battle.attacker_won;
                    response["province_occupied"] = battle.province_occupied;
                    godot::Array outcomes;
                    for (const province::core::ArmyBattleOutcome& outcome : battle.armies) {
                        godot::Dictionary summary;
                        summary["army_id"] =
                            godot::String::utf8(outcome.army_id.value().c_str());
                        summary["casualties"] = outcome.casualties;
                        summary["remaining_manpower"] = outcome.remaining_manpower;
                        summary["destroyed"] = outcome.destroyed;
                        summary["retreat_province"] = outcome.retreat_province.has_value()
                            ? godot::String::utf8(outcome.retreat_province->value().c_str())
                            : godot::String{};
                        outcomes.push_back(summary);
                    }
                    response["battle_outcomes"] = outcomes;
                }
            }
            const province::core::Army* current_army = state_->find_army(
                province::core::ArmyId{army_id.utf8().get_data()}
            );
            response["army_destroyed"] = current_army == nullptr;
            response["army_province_id"] = current_army == nullptr
                ? godot::String{}
                : godot::String::utf8(current_army->province_id.value().c_str());
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::auto_advance_army(const godot::String& army_id) {
    return auto_advance_army_to(army_id, godot::String{});
}

godot::Dictionary ProvinceBridge::auto_advance_army_to(
    const godot::String& army_id,
    const godot::String& target
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::ArmyId core_army_id{army_id.utf8().get_data()};
        const bool has_target = !target.is_empty();
        std::optional<province::core::ProvinceId> target_id;
        if (has_target) {
            target_id.emplace(target.utf8().get_data());
            if (state_->find_province(*target_id) == nullptr) {
                response["accepted"] = false;
                response["error"] = "target province not found";
                return response;
            }
            if (province::core::Army* army = state_->find_army(core_army_id);
                army != nullptr) {
                army->advance_target = *target_id;
                army->advance_enabled = true;
            }
        }
        godot::Array steps;
        std::int32_t total_cost = 0;
        godot::String first_origin;
        godot::String final_destination;
        godot::String last_error;

        const std::size_t maximum_steps = state_->province_count();
        for (std::size_t index = 0; index < maximum_steps; ++index) {
            const province::core::Army* army = state_->find_army(core_army_id);
            if (army == nullptr) {
                if (steps.is_empty()) {
                    response["accepted"] = false;
                    response["error"] = "army not found";
                    return response;
                }
                break;
            }
            const std::optional<province::core::ProvinceId> destination =
                has_target
                    ? province::core::AiSystem{}.find_step_toward(*state_, *army, *target_id)
                    : province::core::AiSystem{}.find_wartime_step(*state_, *army);
            if (!destination.has_value()) {
                last_error = has_target
                    ? godot::String{"army has no path to target"}
                    : godot::String{"army has no wartime path"};
                break;
            }

            godot::Dictionary step = move_army(
                army_id,
                godot::String::utf8(destination->value().c_str())
            );
            if (!step.get("accepted", false)) {
                last_error = step.get("error", "auto advance failed");
                break;
            }

            if (steps.is_empty()) {
                first_origin = step.get("origin", godot::String{});
            }
            final_destination = step.get("destination", godot::String{});
            total_cost += static_cast<std::int32_t>(
                static_cast<std::int64_t>(step.get("movement_cost", 0))
            );
            steps.push_back(step);
            response = step;
            response["auto_destination"] = godot::String::utf8(destination->value().c_str());
            if (has_target) {
                response["auto_target"] = target;
            }

            if (step.get("battle_occurred", false) ||
                step.get("province_occupied", false) ||
                step.get("army_destroyed", false)) {
                break;
            }
        }

        if (steps.is_empty()) {
            response["accepted"] = false;
            response["error"] = last_error.is_empty()
                ? godot::String{"army cannot auto advance"}
                : last_error;
            return response;
        }

        response["accepted"] = true;
        response["auto_steps"] = steps;
        response["auto_step_count"] = static_cast<std::int64_t>(steps.size());
        response["auto_total_movement_cost"] = total_cost;
        response["origin"] = first_origin;
        response["destination"] = final_destination;
        response["movement_cost"] = total_cost;
        if (has_target) {
            response["auto_target"] = target;
            if (province::core::Army* army = state_->find_army(core_army_id);
                army != nullptr && army->province_id == *target_id) {
                army->advance_target.reset();
                response["auto_target_reached"] = true;
            }
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::get_auto_advance_path(
    const godot::String& army_id,
    const godot::String& target
) const {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        if (target.is_empty()) {
            response["accepted"] = false;
            response["error"] = "target province is required";
            return response;
        }
        const province::core::ArmyId core_army_id{army_id.utf8().get_data()};
        const province::core::ProvinceId target_id{target.utf8().get_data()};
        const province::core::Army* army = state_->find_army(core_army_id);
        if (army == nullptr) {
            response["accepted"] = false;
            response["error"] = "army not found";
            return response;
        }
        if (state_->find_province(target_id) == nullptr) {
            response["accepted"] = false;
            response["error"] = "target province not found";
            return response;
        }

        const std::vector<province::core::ProvinceId> path =
            province::core::AiSystem{}.find_path_toward(*state_, *army, target_id);
        if (path.empty()) {
            response["accepted"] = false;
            response["error"] = "army has no path to target";
            return response;
        }

        godot::Array path_ids;
        std::int32_t total_cost = 0;
        std::int32_t first_step_cost = 0;
        for (std::size_t index = 0; index < path.size(); ++index) {
            path_ids.push_back(godot::String::utf8(path[index].value().c_str()));
            if (index > 0) {
                const province::core::Province* province = state_->find_province(path[index]);
                const std::int32_t cost =
                    state_->road_level(path[index - 1], path[index]) ==
                            province::core::RoadLevel::paved
                        ? province::core::MovementSystem::paved_road_cost
                        : province::core::terrain_movement_cost(province->terrain);
                if (index == 1) {
                    first_step_cost = cost;
                }
                total_cost += cost;
            }
        }
        response["accepted"] = true;
        response["path"] = path_ids;
        response["step_count"] = static_cast<std::int64_t>(
            path.size() > 0 ? path.size() - 1 : 0
        );
        response["first_step_cost"] = first_step_cost;
        response["total_movement_cost"] = total_cost;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::set_army_advance_target(
    const godot::String& army_id,
    const godot::String& target
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        province::core::Army* army = state_->find_army(
            province::core::ArmyId{army_id.utf8().get_data()}
        );
        if (army == nullptr) {
            response["accepted"] = false;
            response["error"] = "army not found";
            return response;
        }
        const province::core::ProvinceId target_id{target.utf8().get_data()};
        if (state_->find_province(target_id) == nullptr) {
            response["accepted"] = false;
            response["error"] = "target province not found";
            return response;
        }
        army->advance_target = target_id;
        army->advance_enabled = true;
        army->advance_strategy = "max";
        response["accepted"] = true;
        response["army_id"] = army_id;
        response["advance_target_id"] = target;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::clear_army_advance_target(
    const godot::String& army_id
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        province::core::Army* army = state_->find_army(
            province::core::ArmyId{army_id.utf8().get_data()}
        );
        if (army == nullptr) {
            response["accepted"] = false;
            response["error"] = "army not found";
            return response;
        }
        army->advance_target.reset();
        army->advance_enabled = true;
        response["accepted"] = true;
        response["army_id"] = army_id;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::set_army_advance_enabled(
    const godot::String& army_id,
    const bool enabled
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        province::core::Army* army = state_->find_army(
            province::core::ArmyId{army_id.utf8().get_data()}
        );
        if (army == nullptr) {
            response["accepted"] = false;
            response["error"] = "army not found";
            return response;
        }
        if (!army->advance_target.has_value()) {
            response["accepted"] = false;
            response["error"] = "army has no advance target";
            return response;
        }
        army->advance_enabled = enabled;
        response["accepted"] = true;
        response["army_id"] = army_id;
        response["advance_enabled"] = enabled;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::set_army_advance_strategy(
    const godot::String& army_id,
    const godot::String& strategy
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const std::string strategy_value{strategy.utf8().get_data()};
        if (strategy_value != "max" && strategy_value != "one_step") {
            response["accepted"] = false;
            response["error"] = "advance strategy must be 'max' or 'one_step'";
            return response;
        }
        province::core::Army* army = state_->find_army(
            province::core::ArmyId{army_id.utf8().get_data()}
        );
        if (army == nullptr) {
            response["accepted"] = false;
            response["error"] = "army not found";
            return response;
        }
        if (!army->advance_target.has_value()) {
            response["accepted"] = false;
            response["error"] = "army has no advance target";
            return response;
        }
        army->advance_strategy = strategy_value;
        response["accepted"] = true;
        response["army_id"] = army_id;
        response["advance_strategy"] = strategy;
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Dictionary ProvinceBridge::declare_war(
    const godot::String& aggressor_id,
    const godot::String& defender_id
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::DeclareWarCommand{
                province::core::CountryId{aggressor_id.utf8().get_data()},
                province::core::CountryId{defender_id.utf8().get_data()},
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const province::core::GameEvent& event = result.events.front();
            const auto& war = std::get<province::core::WarDeclaredEvent>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["aggressor_id"] =
                godot::String::utf8(war.aggressor_id.value().c_str());
            response["defender_id"] =
                godot::String::utf8(war.defender_id.value().c_str());
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
}

godot::Array ProvinceBridge::get_diplomatic_relations() const {
    godot::Array summaries;
    if (!state_) {
        return summaries;
    }
    for (const auto& [relation, status] : state_->relations()) {
        godot::Dictionary summary;
        summary["country_a"] = godot::String::utf8(relation.first().value().c_str());
        summary["country_b"] = godot::String::utf8(relation.second().value().c_str());
        summary["status"] = status == province::core::DiplomaticStatus::war
            ? "war"
            : "peace";
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::make_peace(
    const godot::String& country_a,
    const godot::String& country_b,
    const bool annex_occupied_provinces
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::PeaceSettlementPolicy policy = annex_occupied_provinces
            ? province::core::PeaceSettlementPolicy::annex_occupied_provinces
            : province::core::PeaceSettlementPolicy::restore_legal_owners;
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::MakePeaceCommand{
                province::core::CountryId{country_a.utf8().get_data()},
                province::core::CountryId{country_b.utf8().get_data()},
                policy,
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const province::core::GameEvent& event = result.events.front();
            const auto& peace =
                std::get<province::core::PeaceSettlementResult>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["annexed"] =
                peace.policy == province::core::PeaceSettlementPolicy::annex_occupied_provinces;
            godot::Array provinces;
            for (const province::core::PeaceProvinceSettlement& settled : peace.provinces) {
                godot::Dictionary summary;
                summary["province_id"] =
                    godot::String::utf8(settled.province_id.value().c_str());
                summary["legal_owner_before"] =
                    godot::String::utf8(settled.legal_owner_before.value().c_str());
                summary["controller_before"] =
                    godot::String::utf8(settled.controller_before.value().c_str());
                summary["legal_owner_after"] =
                    godot::String::utf8(settled.legal_owner_after.value().c_str());
                provinces.push_back(summary);
            }
            godot::Array armies;
            for (const province::core::ArmyRepatriation& repatriated : peace.armies) {
                godot::Dictionary summary;
                summary["army_id"] =
                    godot::String::utf8(repatriated.army_id.value().c_str());
                summary["origin"] =
                    godot::String::utf8(repatriated.origin.value().c_str());
                summary["destination"] = repatriated.destination.has_value()
                    ? godot::String::utf8(repatriated.destination->value().c_str())
                    : godot::String{};
                summary["disbanded"] = repatriated.disbanded;
                armies.push_back(summary);
            }
            response["provinces"] = provinces;
            response["armies"] = armies;
        }
    } catch (const std::exception& error) {
        response["accepted"] = false;
        response["error"] = godot::String::utf8(error.what());
    }
    return response;
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
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_current_date"),
        &ProvinceBridge::get_current_date
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("advance_turn", "months"),
        &ProvinceBridge::advance_turn
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("build_road", "country_id", "province_a", "province_b"),
        &ProvinceBridge::build_road
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_road_summaries"),
        &ProvinceBridge::get_road_summaries
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("recruit_army", "country_id", "province_id", "manpower"),
        &ProvinceBridge::recruit_army
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_army_summaries"),
        &ProvinceBridge::get_army_summaries
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("move_army", "army_id", "destination"),
        &ProvinceBridge::move_army
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("auto_advance_army", "army_id"),
        &ProvinceBridge::auto_advance_army
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("auto_advance_army_to", "army_id", "target"),
        &ProvinceBridge::auto_advance_army_to
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_auto_advance_path", "army_id", "target"),
        &ProvinceBridge::get_auto_advance_path
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("set_army_advance_target", "army_id", "target"),
        &ProvinceBridge::set_army_advance_target
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("clear_army_advance_target", "army_id"),
        &ProvinceBridge::clear_army_advance_target
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("set_army_advance_enabled", "army_id", "enabled"),
        &ProvinceBridge::set_army_advance_enabled
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("set_army_advance_strategy", "army_id", "strategy"),
        &ProvinceBridge::set_army_advance_strategy
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("declare_war", "aggressor_id", "defender_id"),
        &ProvinceBridge::declare_war
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_diplomatic_relations"),
        &ProvinceBridge::get_diplomatic_relations
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD(
            "make_peace", "country_a", "country_b", "annex_occupied_provinces"
        ),
        &ProvinceBridge::make_peace
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("set_ai_enabled", "enabled", "human_country_id"),
        &ProvinceBridge::set_ai_enabled
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("is_ai_enabled"),
        &ProvinceBridge::is_ai_enabled
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_technology_summaries"),
        &ProvinceBridge::get_technology_summaries
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("research_technology", "country_id", "track"),
        &ProvinceBridge::research_technology
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("save_game", "path"),
        &ProvinceBridge::save_game
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("load_game", "path"),
        &ProvinceBridge::load_game
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_game_status", "player_country_id"),
        &ProvinceBridge::get_game_status
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_war_summaries"),
        &ProvinceBridge::get_war_summaries
    );
    godot::ClassDB::bind_method(
        godot::D_METHOD("get_frontline_edges"),
        &ProvinceBridge::get_frontline_edges
    );
}

} // namespace province::bridge
