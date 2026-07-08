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
        summary["neighbor_count"] = static_cast<std::int64_t>(province.neighbors.size());
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
    godot::Array ai_actions;
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
            } else if (event.type == province::core::GameEventType::battle_resolved) {
                action["type"] = "battle_resolved";
            } else {
                action["type"] = "other";
            }
            ai_actions.push_back(action);
        }
    }
    response["incomes"] = incomes;
    response["population_changes"] = population_changes;
    response["ai_actions"] = ai_actions;
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
}

} // namespace province::bridge
