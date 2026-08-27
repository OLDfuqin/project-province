#include "province_bridge.hpp"

#include "province/core/ai_system.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_status.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/order_system.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/save_game.hpp"
#include "province/core/version.hpp"

#include <filesystem>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <vector>

namespace province::bridge {
namespace {

[[nodiscard]] double movement_points_to_display(const std::int32_t half_points) noexcept {
    return static_cast<double>(half_points) /
        province::core::MovementSystem::movement_point_scale;
}

[[nodiscard]] godot::String technology_track_name(
    const province::core::TechnologyTrack track
) {
    switch (track) {
        case province::core::TechnologyTrack::economy:
            return "economy";
        case province::core::TechnologyTrack::military:
            return "military";
        case province::core::TechnologyTrack::roads:
            return "roads";
    }
    throw std::logic_error{"invalid technology track"};
}

[[nodiscard]] province::core::CountryId order_country_id(
    const province::core::GameOrder& order
) {
    return std::visit([](const auto& typed_order) {
        return typed_order.country_id;
    }, order);
}

void append_order_fields(
    godot::Dictionary& target,
    const province::core::GameOrder& order
) {
    target["order_id"] = godot::String::utf8(
        province::core::order_id(order).value().c_str()
    );
    target["country_id"] = godot::String::utf8(
        order_country_id(order).value().c_str()
    );
    target["status"] = "pending";
    std::visit([&target](const auto& typed_order) {
        using OrderType = std::decay_t<decltype(typed_order)>;
        if constexpr (std::is_same_v<OrderType, province::core::ArmyActionOrder>) {
            target["type"] = "army_action";
            target["order_type"] = "army_action";
            target["army_id"] = godot::String::utf8(typed_order.army_id.value().c_str());
            target["origin"] = godot::String::utf8(typed_order.origin.value().c_str());
            target["destination"] = godot::String::utf8(
                typed_order.destination.value().c_str()
            );
            godot::Array path;
            for (const province::core::ProvinceId& province_id : typed_order.path) {
                path.push_back(godot::String::utf8(province_id.value().c_str()));
            }
            target["path"] = path;
            target["is_attack"] = typed_order.is_attack;
            target["reserved_movement_half"] = typed_order.reserved_movement_half;
            target["movement_cost"] = movement_points_to_display(
                typed_order.reserved_movement_half
            );
            target["remaining_months"] = 1;
        } else if constexpr (
            std::is_same_v<OrderType, province::core::RecruitmentOrder>
        ) {
            target["type"] = "recruitment";
            target["order_type"] = "recruitment";
            target["province_id"] = godot::String::utf8(
                typed_order.province_id.value().c_str()
            );
            target["manpower"] = typed_order.manpower;
            target["paid_cost"] = typed_order.paid_cost;
            target["cost"] = typed_order.paid_cost;
            target["remaining_months"] = typed_order.remaining_months;
        } else if constexpr (
            std::is_same_v<OrderType, province::core::RoadConstructionOrder>
        ) {
            target["type"] = "road_construction";
            target["order_type"] = "road_construction";
            target["province_a"] = godot::String::utf8(
                typed_order.province_a.value().c_str()
            );
            target["province_b"] = godot::String::utf8(
                typed_order.province_b.value().c_str()
            );
            target["paid_cost"] = typed_order.paid_cost;
            target["cost"] = typed_order.paid_cost;
            target["remaining_months"] = typed_order.remaining_months;
        } else if constexpr (std::is_same_v<OrderType, province::core::ResearchOrder>) {
            target["type"] = "research";
            target["order_type"] = "research";
            target["track"] = technology_track_name(typed_order.track);
            target["previous_level"] = typed_order.previous_level;
            target["target_level"] = typed_order.target_level;
            target["paid_cost"] = typed_order.paid_cost;
            target["cost"] = typed_order.paid_cost;
            target["remaining_months"] = typed_order.remaining_months;
        } else if constexpr (
            std::is_same_v<OrderType, province::core::WarDeclarationOrder>
        ) {
            target["type"] = "war_declaration";
            target["order_type"] = "war_declaration";
            target["defender_id"] = godot::String::utf8(
                typed_order.defender_id.value().c_str()
            );
            target["remaining_months"] = 1;
        }
    }, order);
}

void set_stable_rejection(
    godot::Dictionary& response,
    const char* const message
) {
    response["accepted"] = false;
    response["error"] = message;
}

void append_order_cancellation_fields(
    godot::Dictionary& target,
    const province::core::OrderCancelledEvent& cancelled
) {
    target["order_id"] = godot::String::utf8(cancelled.order_id.value().c_str());
    target["country_id"] = godot::String::utf8(cancelled.country_id.value().c_str());
    target["army_id"] = cancelled.army_id.has_value()
        ? godot::String::utf8(cancelled.army_id->value().c_str())
        : godot::String{};
    target["refunded_cost"] = cancelled.refunded_cost;
    target["refunded_movement_half"] = cancelled.refunded_movement_half;
    target["reason"] = godot::String::utf8(cancelled.reason.c_str());
}

bool append_created_order_response(
    godot::Dictionary& response,
    const province::core::CommandResult& result,
    const province::core::GameState& state
) {
    for (const province::core::GameEvent& event : result.events) {
        if (event.type != province::core::GameEventType::order_created) continue;
        const province::core::OrderId& id =
            std::get<province::core::OrderCreatedEvent>(event.payload).order_id;
        const auto found = state.orders().find(id);
        if (found == state.orders().end()) return false;
        append_order_fields(response, found->second);
        response["status"] = "queued";
        response["event_type"] = "order_created";
        response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
        return true;
    }
    return false;
}

[[nodiscard]] godot::String battle_result_name(
    const province::core::BattleResultType result
) {
    switch (result) {
        case province::core::BattleResultType::defender_victory:
            return "defender_victory";
        case province::core::BattleResultType::attacker_victory:
            return "attacker_victory";
        case province::core::BattleResultType::mutual_destruction:
            return "mutual_destruction";
    }
    throw std::logic_error{"invalid battle result type"};
}

[[nodiscard]] double random_tenths_to_display(const std::int32_t value) noexcept {
    return static_cast<double>(value) / 10.0;
}

void append_battle_metadata(
    godot::Dictionary& target,
    const province::core::BattleResolution& battle
) {
    target["battle_occurred"] = battle.occurred;
    target["attacker_won"] = battle.occurred && battle.attacker_won;
    target["province_occupied"] = battle.province_occupied;
    target["province_id"] = godot::String::utf8(battle.province_id.value().c_str());
    target["attacker_id"] = godot::String::utf8(battle.attacker_id.value().c_str());
    target["defender_id"] = godot::String::utf8(battle.defender_id.value().c_str());
    if (battle.occurred) {
        target["battle_result"] = battle_result_name(battle.result);
        target["attacker_random_x"] = random_tenths_to_display(battle.attacker_random_tenths);
        target["defender_random_x"] = random_tenths_to_display(battle.defender_random_tenths);
        target["attacker_initial_manpower"] = battle.attacker_initial_manpower;
        target["defender_initial_manpower"] = battle.defender_initial_manpower;
        target["attacker_military_level"] = battle.attacker_military_level;
        target["defender_military_level"] = battle.defender_military_level;
        target["attacker_base_strength"] = battle.attacker_base_strength;
        target["defender_base_strength"] = battle.defender_base_strength;
        target["defender_final_strength"] = battle.defender_final_strength;
        target["terrain_defense_bonus"] = battle.terrain_defense_bonus;
        target["attacker_casualties"] = battle.attacker_casualties;
        target["defender_casualties"] = battle.defender_casualties;
        target["attacker_remaining_manpower"] = battle.attacker_remaining_manpower;
        target["defender_remaining_manpower"] = battle.defender_remaining_manpower;
    }

    std::int64_t casualties = 0;
    godot::Array outcomes;
    for (const province::core::ArmyBattleOutcome& outcome : battle.armies) {
        casualties += outcome.casualties;
        godot::Dictionary summary;
        summary["army_id"] = godot::String::utf8(outcome.army_id.value().c_str());
        summary["display_name"] = godot::String::utf8(outcome.display_name.c_str());
        summary["casualties"] = outcome.casualties;
        summary["remaining_manpower"] = outcome.remaining_manpower;
        summary["destroyed"] = outcome.destroyed;
        summary["retreat_province"] = outcome.retreat_province.has_value()
            ? godot::String::utf8(outcome.retreat_province->value().c_str())
            : godot::String{};
        outcomes.push_back(summary);
    }
    target["casualties"] = casualties;
    target["battle_outcomes"] = outcomes;
}

}

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
        player_country_id_ = province::core::CountryId{"auroria"};
        command_processor_.enable_ai(*state_, *player_country_id_);
        last_error_ = godot::String{};
        return true;
    } catch (const std::exception&) {
        state_.reset();
        last_error_ = "scenario could not be loaded";
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
        if (country.hidden) {
            continue;
        }
        std::int64_t province_count = 0;
        std::int64_t economy = 0;
        std::int64_t fiscal_income = 0;
        for (const auto& [province_id, province] : state_->provinces()) {
            static_cast<void>(province);
            if (state_->controller_of(province_id) == country_id) {
                ++province_count;
                economy += province::core::EconomySystem::province_economy(
                    *state_, province_id
                );
                fiscal_income += province::core::EconomySystem::province_fiscal_income(
                    *state_, province_id
                );
            }
        }

        godot::Dictionary summary;
        summary["id"] = godot::String::utf8(country_id.value().c_str());
        summary["name"] = godot::String::utf8(country.name.c_str());
        summary["code"] = godot::String::utf8(country.code.c_str());
        summary["color_rgb"] = static_cast<std::int64_t>(country.color_rgb);
        summary["treasury"] = country.treasury;
        summary["province_count"] = province_count;
        summary["economy"] = economy;
        summary["fiscal_income"] = fiscal_income;
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
        summary["recruitable_population"] = province.recruitable_population;
        summary["economy"] = province::core::EconomySystem::province_economy(
            *state_, province_id
        );
        summary["fiscal_income"] =
            province::core::EconomySystem::province_fiscal_income(*state_, province_id);
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

godot::Array ProvinceBridge::get_pending_orders(
    const godot::String& country_id
) const {
    godot::Array summaries;
    if (!state_) return summaries;
    try {
        const province::core::CountryId requested{country_id.utf8().get_data()};
        if (player_country_id_.has_value() && requested != *player_country_id_) {
            return summaries;
        }
        for (const auto& [id, order] : state_->orders()) {
            static_cast<void>(id);
            if (order_country_id(order) != requested) continue;
            godot::Dictionary summary;
            append_order_fields(summary, order);
            summaries.push_back(summary);
        }
    } catch (const std::exception&) {
        return godot::Array{};
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::cancel_order(const godot::String& order_id) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    if (!player_country_id_.has_value()) {
        response["accepted"] = false;
        response["error"] = "player country is not configured";
        return response;
    }
    try {
        const province::core::OrderId id{order_id.utf8().get_data()};
        const auto found = state_->orders().find(id);
        if (found != state_->orders().end() && player_country_id_.has_value() &&
            order_country_id(found->second) != *player_country_id_) {
            response["accepted"] = false;
            response["error"] = "cannot cancel another country's order";
            return response;
        }
        const province::core::CommandResult result = command_processor_.execute(
            *state_, province::core::CancelOrderCommand{id}
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted && !result.events.empty()) {
            const auto& cancelled = std::get<province::core::OrderCancelledEvent>(
                result.events.front().payload
            );
            response["status"] = "cancelled";
            response["event_type"] = "order_cancelled";
            response["event_sequence"] =
                static_cast<std::int64_t>(result.events.front().sequence);
            append_order_cancellation_fields(response, cancelled);
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "order could not be cancelled");
    }
    return response;
}

godot::Array ProvinceBridge::get_army_order_targets(
    const godot::String& army_id
) const {
    godot::Array targets;
    if (!state_) return targets;
    try {
        const province::core::ArmyId id{army_id.utf8().get_data()};
        const province::core::Army* army = state_->find_army(id);
        if (army == nullptr || (player_country_id_.has_value() &&
                army->owner_id != *player_country_id_)) {
            return targets;
        }
        for (const auto& [pending_id, pending] : state_->orders()) {
            static_cast<void>(pending_id);
            const auto* action = std::get_if<province::core::ArmyActionOrder>(&pending);
            if (action != nullptr && action->army_id == id) return targets;
        }
        const province::core::MovementSystem movement;
        for (const auto& [province_id, province] : state_->provinces()) {
            static_cast<void>(province);
            const std::vector<province::core::ProvinceId> path =
                movement.find_order_path(*state_, id, province_id);
            if (path.empty()) continue;
            const bool is_attack = state_->controller_of(province_id) != army->owner_id;
            province::core::GameState preview = *state_;
            const province::core::OrderOperationResult queued =
                province::core::OrderSystem{}.queue_army_action(
                    preview, id, path, is_attack
                );
            if (!queued.accepted || !queued.order_id.has_value()) continue;
            const auto* action = std::get_if<province::core::ArmyActionOrder>(
                &preview.orders().at(*queued.order_id)
            );
            if (action == nullptr) continue;
            godot::Dictionary target;
            target["province_id"] = godot::String::utf8(province_id.value().c_str());
            target["is_attack"] = is_attack;
            target["reserved_movement_half"] = action->reserved_movement_half;
            target["movement_cost"] = movement_points_to_display(
                action->reserved_movement_half
            );
            godot::Array serialized_path;
            for (const province::core::ProvinceId& step : path) {
                serialized_path.push_back(godot::String::utf8(step.value().c_str()));
            }
            target["path"] = serialized_path;
            targets.push_back(target);
        }
    } catch (const std::exception&) {
        return godot::Array{};
    }
    return targets;
}

godot::Dictionary ProvinceBridge::get_recruitment_order_quote(
    const godot::String& country_id,
    const godot::String& province_id,
    const std::int64_t manpower
) const {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        province::core::GameState preview = *state_;
        const province::core::OrderOperationResult result =
            province::core::OrderSystem{}.queue_recruitment(
                preview,
                province::core::CountryId{country_id.utf8().get_data()},
                province::core::ProvinceId{province_id.utf8().get_data()},
                manpower
            );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted && result.order_id.has_value()) {
            append_order_fields(response, preview.orders().at(*result.order_id));
            response["status"] = "quote";
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "recruitment quote could not be calculated");
    }
    return response;
}

godot::Dictionary ProvinceBridge::get_road_order_quote(
    const godot::String& country_id,
    const godot::String& province_a,
    const godot::String& province_b
) const {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        province::core::GameState preview = *state_;
        const province::core::OrderOperationResult result =
            province::core::OrderSystem{}.queue_road_construction(
                preview,
                province::core::CountryId{country_id.utf8().get_data()},
                province::core::ProvinceId{province_a.utf8().get_data()},
                province::core::ProvinceId{province_b.utf8().get_data()}
            );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted && result.order_id.has_value()) {
            append_order_fields(response, preview.orders().at(*result.order_id));
            response["status"] = "quote";
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "road quote could not be calculated");
    }
    return response;
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

    godot::Array fiscal_incomes;
    godot::Array maintenance_charges;
    godot::Array population_changes;
    godot::Array movement_grants;
    godot::Array turn_actions;
    for (const province::core::GameEvent& event : result.events) {
        if (event.type == province::core::GameEventType::fiscal_income_resolved) {
            const auto& fiscal =
                std::get<province::core::FiscalIncomeResolvedEvent>(event.payload);
            for (const province::core::CountryFiscalIncome& income : fiscal.fiscal_incomes) {
                godot::Dictionary summary;
                summary["country_id"] = godot::String::utf8(
                    income.country_id.value().c_str()
                );
                summary["amount"] = income.amount;
                fiscal_incomes.push_back(summary);
            }
            response["fiscal_income_event_sequence"] =
                static_cast<std::int64_t>(event.sequence);
            continue;
        }
        if (event.type == province::core::GameEventType::population_resolved) {
            const auto& population =
                std::get<province::core::PopulationResolvedEvent>(event.payload);
            for (const province::core::ProvincePopulationChange& change : population.changes) {
                godot::Dictionary summary;
                summary["province_id"] = godot::String::utf8(
                    change.province_id.value().c_str()
                );
                summary["previous_population"] = change.previous_population;
                summary["current_population"] = change.current_population;
                summary["growth"] = change.growth;
                summary["previous_recruitable_population"] =
                    change.previous_recruitable_population;
                summary["current_recruitable_population"] =
                    change.current_recruitable_population;
                summary["recruitable_growth"] = change.recruitable_growth;
                population_changes.push_back(summary);
            }
            response["population_event_sequence"] =
                static_cast<std::int64_t>(event.sequence);
            continue;
        }
        if (event.type == province::core::GameEventType::turn_advanced) {
            const auto& turn = std::get<province::core::TurnAdvancedEvent>(event.payload);
            response["event_sequence"] = static_cast<std::int64_t>(event.sequence);
            response["event_type"] = "turn_advanced";
            response["elapsed_months"] = turn.elapsed_months;
            response["previous_year"] = turn.previous_year;
            response["previous_month"] = turn.previous_month;
            response["year"] = turn.current_year;
            response["month"] = turn.current_month;
            continue;
        }

        godot::Dictionary action;
        action["event_sequence"] = static_cast<std::int64_t>(event.sequence);
        if (event.type == province::core::GameEventType::maintenance_resolved) {
            const auto& maintenance =
                std::get<province::core::MaintenanceResolvedEvent>(event.payload);
            godot::Array charges;
            for (const province::core::CountryMaintenanceCharge& charge :
                    maintenance.charges) {
                godot::Dictionary summary;
                summary["country_id"] = godot::String::utf8(
                    charge.country_id.value().c_str()
                );
                summary["amount"] = charge.amount;
                charges.push_back(summary);
                maintenance_charges.push_back(summary);
            }
            action["type"] = "maintenance_resolved";
            action["elapsed_months"] = maintenance.elapsed_months;
            action["charges"] = charges;
        } else if (event.type == province::core::GameEventType::movement_points_granted) {
            const auto& movement =
                std::get<province::core::MovementPointsGrantedEvent>(event.payload);
            godot::Array grants;
            for (const province::core::ArmyMovementGrant& grant : movement.grants) {
                godot::Dictionary summary;
                summary["army_id"] = godot::String::utf8(grant.army_id.value().c_str());
                summary["amount"] = movement_points_to_display(grant.amount);
                summary["current_points"] = movement_points_to_display(grant.current_points);
                grants.push_back(summary);
                movement_grants.push_back(summary);
            }
            action["type"] = "movement_points_granted";
            action["elapsed_months"] = movement.elapsed_months;
            action["grants"] = grants;
        } else if (event.type == province::core::GameEventType::army_recruited) {
            const auto& recruited =
                std::get<province::core::ArmyRecruitedEvent>(event.payload);
            action["type"] = "army_recruited";
            action["order_id"] = godot::String::utf8(recruited.order_id.value().c_str());
            action["army_id"] = godot::String::utf8(recruited.army_id.value().c_str());
            action["country_id"] = godot::String::utf8(
                recruited.country_id.value().c_str()
            );
            action["province_id"] = godot::String::utf8(
                recruited.province_id.value().c_str()
            );
            action["manpower"] = recruited.manpower;
            action["cost"] = recruited.cost;
        } else if (event.type == province::core::GameEventType::army_renamed) {
            const auto& renamed = std::get<province::core::ArmyRenamedEvent>(event.payload);
            action["type"] = "army_renamed";
            action["army_id"] = godot::String::utf8(renamed.army_id.value().c_str());
            action["country_id"] = godot::String::utf8(renamed.country_id.value().c_str());
            action["previous_formation_number"] = renamed.previous_formation_number;
            action["formation_number"] = renamed.current_formation_number;
        } else if (event.type == province::core::GameEventType::armies_merged) {
            const auto& merged = std::get<province::core::ArmiesMergedEvent>(event.payload);
            action["type"] = "armies_merged";
            action["country_id"] = godot::String::utf8(merged.country_id.value().c_str());
            action["province_id"] = godot::String::utf8(merged.province_id.value().c_str());
            action["primary_army_id"] = godot::String::utf8(
                merged.primary_army_id.value().c_str()
            );
            godot::Array merged_ids;
            for (const province::core::ArmyId& id : merged.merged_army_ids) {
                merged_ids.push_back(godot::String::utf8(id.value().c_str()));
            }
            action["merged_army_ids"] = merged_ids;
            action["previous_manpower"] = merged.previous_manpower;
            action["current_manpower"] = merged.current_manpower;
            action["movement_points"] = movement_points_to_display(
                merged.current_movement_points
            );
            action["formation_number"] = merged.formation_number;
            action["display_name"] = godot::String::utf8(merged.display_name.c_str());
            action["automatic"] = merged.automatic;
        } else if (event.type == province::core::GameEventType::army_moved) {
            const auto& moved = std::get<province::core::ArmyMovedEvent>(event.payload);
            action["type"] = "army_moved";
            action["order_id"] = godot::String::utf8(moved.order_id.value().c_str());
            action["army_id"] = godot::String::utf8(moved.army_id.value().c_str());
            action["origin"] = godot::String::utf8(moved.origin.value().c_str());
            action["destination"] = godot::String::utf8(moved.destination.value().c_str());
            action["movement_cost"] = movement_points_to_display(moved.movement_cost_half);
            action["remaining_points"] = movement_points_to_display(
                moved.remaining_movement_half
            );
            action["converted_from_attack"] = moved.converted_from_attack;
        } else if (event.type == province::core::GameEventType::battle_resolved) {
            const auto& resolved =
                std::get<province::core::BattleResolvedEvent>(event.payload);
            action["type"] = "battle_resolved";
            godot::Array order_ids;
            for (const province::core::OrderId& id : resolved.order_ids) {
                order_ids.push_back(godot::String::utf8(id.value().c_str()));
            }
            action["order_ids"] = order_ids;
            append_battle_metadata(action, resolved.battle);
        } else if (event.type == province::core::GameEventType::road_built) {
            const auto& road = std::get<province::core::RoadBuiltEvent>(event.payload);
            action["type"] = "road_built";
            action["order_id"] = godot::String::utf8(road.order_id.value().c_str());
            action["country_id"] = godot::String::utf8(road.country_id.value().c_str());
            action["province_a"] = godot::String::utf8(road.province_a.value().c_str());
            action["province_b"] = godot::String::utf8(road.province_b.value().c_str());
            action["level"] = road.level == province::core::RoadLevel::paved
                ? "paved" : "none";
            action["cost"] = road.cost;
        } else if (event.type == province::core::GameEventType::war_declared) {
            const auto& war = std::get<province::core::WarDeclaredEvent>(event.payload);
            action["type"] = "war_declared";
            action["order_id"] = war.order_id.has_value()
                ? godot::String::utf8(war.order_id->value().c_str())
                : godot::String{};
            action["country_id"] = godot::String::utf8(war.aggressor_id.value().c_str());
            action["target_id"] = godot::String::utf8(war.defender_id.value().c_str());
        } else if (event.type == province::core::GameEventType::peace_made) {
            const auto& peace =
                std::get<province::core::PeaceSettlementResult>(event.payload);
            action["type"] = "peace_made";
            action["country_a"] = godot::String::utf8(peace.country_a.value().c_str());
            action["country_b"] = godot::String::utf8(peace.country_b.value().c_str());
            action["province_count"] = static_cast<std::int64_t>(peace.provinces.size());
            action["army_count"] = static_cast<std::int64_t>(peace.armies.size());
        } else if (event.type == province::core::GameEventType::technology_researched) {
            const auto& researched =
                std::get<province::core::TechnologyResearchedEvent>(event.payload);
            const province::core::TechnologyResearchResult& research = researched.result;
            action["type"] = "technology_researched";
            action["order_id"] = godot::String::utf8(researched.order_id.value().c_str());
            action["country_id"] = godot::String::utf8(
                research.country_id.value().c_str()
            );
            action["track"] = technology_track_name(research.track);
            action["previous_level"] = research.previous_level;
            action["current_level"] = research.current_level;
            action["cost"] = research.cost;
        } else if (event.type == province::core::GameEventType::order_created) {
            const auto& created = std::get<province::core::OrderCreatedEvent>(event.payload);
            action["type"] = "order_created";
            action["order_id"] = godot::String::utf8(created.order_id.value().c_str());
        } else if (event.type == province::core::GameEventType::order_cancelled) {
            const auto& cancelled =
                std::get<province::core::OrderCancelledEvent>(event.payload);
            action["type"] = "order_cancelled";
            action["status"] = "cancelled";
            append_order_cancellation_fields(action, cancelled);
        } else {
            continue;
        }
        action["event_type"] = action["type"];
        turn_actions.push_back(action);
    }
    response["fiscal_incomes"] = fiscal_incomes;
    response["maintenance_charges"] = maintenance_charges;
    response["population_changes"] = population_changes;
    response["movement_grants"] = movement_grants;
    response["turn_actions"] = turn_actions;
    response["ai_actions"] = turn_actions;
    return response;
}

bool ProvinceBridge::set_ai_enabled(
    const bool enabled,
    const godot::String& human_country_id
) {
    constexpr const char* rejection = "ai configuration could not be changed";
    try {
        if (!state_) {
            last_error_ = rejection;
            return false;
        }

        const godot::CharString utf8_id = human_country_id.utf8();
        const province::core::CountryId requested_player{
            std::string{utf8_id.get_data()}
        };
        const province::core::Country* country = state_->find_country(requested_player);
        if (country == nullptr || country->hidden) {
            last_error_ = rejection;
            return false;
        }

        // Enabling AI may queue orders. Perform the entire operation on copies
        // so any rejection or exception leaves player authority, AI state and
        // the live order queue unchanged.
        province::core::GameState working_state = *state_;
        province::core::CommandProcessor working_processor = command_processor_;
        if (enabled) {
            working_processor.enable_ai(working_state, requested_player);
        } else {
            working_processor.disable_ai();
        }

        state_ = std::move(working_state);
        command_processor_ = std::move(working_processor);
        player_country_id_ = requested_player;
        last_error_ = godot::String{};
        return true;
    } catch (...) {
        // Never expose exception payloads across the GDExtension ABI boundary.
        last_error_ = rejection;
        return false;
    }
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
        const province::core::Country* country = state_->find_country(country_id);
        if (country == nullptr || country->hidden) {
            continue;
        }
        godot::Dictionary summary;
        summary["country_id"] = godot::String::utf8(country_id.value().c_str());
        summary["economy_level"] = technology.economy_level;
        summary["military_level"] = technology.military_level;
        summary["roads_level"] = technology.roads_level;
        summary["economy_cost"] = technology.economy_level <
                province::core::TechnologySystem::maximum_level(
                    province::core::TechnologyTrack::economy
                )
            ? province::core::TechnologySystem::research_cost(technology.economy_level)
            : 0;
        summary["military_cost"] = technology.military_level <
                province::core::TechnologySystem::maximum_level(
                    province::core::TechnologyTrack::military
                )
            ? province::core::TechnologySystem::research_cost(technology.military_level)
            : 0;
        summary["roads_cost"] = technology.roads_level <
                province::core::TechnologySystem::maximum_level(
                    province::core::TechnologyTrack::roads
                )
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
        if (result.accepted && !append_created_order_response(response, result, *state_)) {
            response["accepted"] = false;
            response["error"] = "research order response is missing its created order";
        } else if (result.accepted) {
            // Compatibility until the planning UI consumes target_level directly.
            response["current_level"] = response["target_level"];
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "research order could not be created");
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
    if (!player_country_id_.has_value()) {
        response["accepted"] = false;
        response["error"] = "player country is not configured";
        return response;
    }
    try {
        const godot::CharString utf8_path = path.utf8();
        province::core::SaveGameSerializer::save(
            std::filesystem::u8path(utf8_path.get_data()),
            *state_,
            command_processor_.next_event_sequence(),
            *player_country_id_,
            command_processor_.human_country_id()
        );
        response["accepted"] = true;
        response["error"] = godot::String{};
        response["path"] = path;
    } catch (const std::exception&) {
        response["accepted"] = false;
        response["error"] = "save game could not be written";
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
        if (loaded.ai_human_country_id.has_value()) {
            restored_processor.enable_ai(*loaded.ai_human_country_id);
        }
        const province::core::CountryId restored_player = loaded.player_country_id;
        state_ = std::move(loaded.state);
        command_processor_ = std::move(restored_processor);
        player_country_id_ = restored_player;
        last_error_ = godot::String{};
        response["accepted"] = true;
        response["error"] = godot::String{};
        response["path"] = path;
        response["year"] = state_->clock().year();
        response["month"] = state_->clock().month();
    } catch (const std::exception&) {
        response["accepted"] = false;
        // SaveGameSerializer is part of the core library while this boundary is
        // loaded as a GDExtension DLL. Keep exception text on the core side of
        // that boundary: dereferencing std::exception::what() here is not ABI
        // safe across independently configured MSVC runtimes.
        response["error"] = "save game could not be loaded";
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
        const province::core::Country* country = state_->find_country(country_id);
        if (country == nullptr || country->hidden) {
            continue;
        }
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
        const province::core::Country* first_country = state_->find_country(first);
        const province::core::Country* second_country = state_->find_country(second);
        if (first_country == nullptr || second_country == nullptr ||
            first_country->hidden || second_country->hidden) {
            continue;
        }
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
        if (result.accepted && !append_created_order_response(response, result, *state_)) {
            response["accepted"] = false;
            response["error"] = "road order response is missing its created order";
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "road order could not be created");
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
        if (result.accepted && !append_created_order_response(response, result, *state_)) {
            response["accepted"] = false;
            response["error"] = "recruitment order response is missing its created order";
        } else if (result.accepted) {
            // A delayed recruitment has no ArmyId until project completion.
            response["army_id"] = godot::String{};
            response["display_name"] = godot::String{};
            response["formation_number"] = 0;
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "recruitment order could not be created");
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
        const province::core::Country* country = state_->find_country(army.owner_id);
        summary["formation_number"] = army.formation_number;
        summary["country_code"] = country == nullptr
            ? godot::String{}
            : godot::String::utf8(country->code.c_str());
        const std::string display_name = state_->army_display_name(army_id);
        summary["display_name"] = godot::String::utf8(display_name.c_str());
        summary["province_id"] = godot::String::utf8(army.province_id.value().c_str());
        summary["manpower"] = army.manpower;
        summary["movement_points"] = movement_points_to_display(army.movement_points);
        const province::core::CountryTechnology* technology =
            state_->find_technology(army.owner_id);
        const std::int32_t military_level = technology == nullptr
            ? 0
            : technology->military_level;
        summary["max_movement_points"] = movement_points_to_display(
            province::core::MovementSystem::maximum_movement_points_half(military_level)
        );
        summary["monthly_movement_grant"] = movement_points_to_display(
            province::core::MovementSystem::monthly_movement_points_half(military_level)
        );
        summary["advance_target_id"] = army.advance_target.has_value()
            ? godot::String::utf8(army.advance_target->value().c_str())
            : godot::String{};
        summary["advance_enabled"] = army.advance_enabled;
        summary["advance_strategy"] = godot::String::utf8(army.advance_strategy.c_str());
        summaries.push_back(summary);
    }
    return summaries;
}

godot::Dictionary ProvinceBridge::rename_army(
    const godot::String& army_id,
    const std::int64_t formation_number
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        const province::core::ArmyId core_army_id{army_id.utf8().get_data()};
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::RenameArmyCommand{core_army_id, formation_number}
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const auto& renamed = std::get<province::core::ArmyRenamedEvent>(
                result.events.front().payload
            );
            response["event_sequence"] =
                static_cast<std::int64_t>(result.events.front().sequence);
            response["army_id"] = army_id;
            response["previous_formation_number"] =
                renamed.previous_formation_number;
            response["formation_number"] = renamed.current_formation_number;
            const std::string display_name = state_->army_display_name(core_army_id);
            response["display_name"] = godot::String::utf8(display_name.c_str());
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "army could not be renamed");
    }
    return response;
}

godot::Dictionary ProvinceBridge::merge_armies(
    const godot::String& primary_army_id,
    const godot::Array& merged_army_ids
) {
    godot::Dictionary response;
    if (!state_) {
        response["accepted"] = false;
        response["error"] = "no scenario is loaded";
        return response;
    }
    try {
        std::vector<province::core::ArmyId> core_merged_ids;
        core_merged_ids.reserve(merged_army_ids.size());
        for (std::int64_t index = 0; index < merged_army_ids.size(); ++index) {
            const godot::String merged_id = merged_army_ids[index];
            core_merged_ids.emplace_back(merged_id.utf8().get_data());
        }
        const province::core::CommandResult result = command_processor_.execute(
            *state_,
            province::core::MergeArmiesCommand{
                province::core::ArmyId{primary_army_id.utf8().get_data()},
                std::move(core_merged_ids),
            }
        );
        response["accepted"] = result.accepted;
        response["error"] = godot::String::utf8(result.error.c_str());
        if (result.accepted) {
            const auto& merged = std::get<province::core::ArmiesMergedEvent>(
                result.events.front().payload
            );
            godot::Array merged_ids;
            for (const province::core::ArmyId& merged_id : merged.merged_army_ids) {
                merged_ids.push_back(godot::String::utf8(merged_id.value().c_str()));
            }
            response["event_sequence"] =
                static_cast<std::int64_t>(result.events.front().sequence);
            response["primary_army_id"] = primary_army_id;
            response["merged_army_ids"] = merged_ids;
            response["previous_manpower"] = merged.previous_manpower;
            response["current_manpower"] = merged.current_manpower;
            response["movement_points"] = movement_points_to_display(
                merged.current_movement_points
            );
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "armies could not be merged");
    }
    return response;
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
        if (result.accepted && !append_created_order_response(response, result, *state_)) {
            response["accepted"] = false;
            response["error"] = "army action response is missing its created order";
        } else if (result.accepted) {
            const province::core::Army* army = state_->find_army(
                province::core::ArmyId{army_id.utf8().get_data()}
            );
            response["remaining_points"] = army == nullptr
                ? 0.0
                : movement_points_to_display(army->movement_points);
            response["army_destroyed"] = false;
            response["army_province_id"] = response["origin"];
        }
    } catch (const std::exception&) {
        set_stable_rejection(response, "army order could not be created");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "army could not auto advance");
    }
    return response;
}

godot::Dictionary ProvinceBridge::get_auto_advance_path(
    const godot::String& army_id,
    const godot::String& target
) const {
    return get_auto_advance_path_for_months(army_id, target, 0);
}

godot::Dictionary ProvinceBridge::get_auto_advance_path_for_months(
    const godot::String& army_id,
    const godot::String& target,
    const std::int32_t months
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
        if (months < 0) {
            response["accepted"] = false;
            response["error"] = "preview months cannot be negative";
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
        const province::core::CountryTechnology* technology =
            state_->find_technology(army->owner_id);
        if (technology == nullptr) {
            response["accepted"] = false;
            response["error"] = "army owner has no technology state";
            return response;
        }
        const std::int32_t monthly_grant_half =
            province::core::MovementSystem::monthly_movement_points_half(
                technology->military_level
            );
        const std::int64_t movement_granted_half =
            static_cast<std::int64_t>(months) * monthly_grant_half;
        const std::int64_t preview_available_movement_half =
            static_cast<std::int64_t>(army->movement_points) + movement_granted_half;

        const std::vector<province::core::ProvinceId> path =
            province::core::AiSystem{}.find_path_toward(*state_, *army, target_id);
        if (path.empty()) {
            response["accepted"] = false;
            response["error"] = "army has no path to target";
            return response;
        }

        godot::Array path_ids;
        godot::Array preview_path_ids;
        std::int32_t total_cost = 0;
        std::int32_t first_step_cost = 0;
        std::int32_t preview_cost = 0;
        std::int64_t preview_steps = 0;
        province::core::ProvinceId preview_destination = army->province_id;
        std::string preview_stop_reason{"target_reached"};
        for (std::size_t index = 0; index < path.size(); ++index) {
            path_ids.push_back(godot::String::utf8(path[index].value().c_str()));
            if (index == 0) {
                preview_path_ids.push_back(godot::String::utf8(path[index].value().c_str()));
            }
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
                if (preview_stop_reason != "target_reached") {
                    continue;
                }
                if (army->advance_strategy == "stop_before_enemy" &&
                    state_->controller_of(path[index]) != army->owner_id) {
                    preview_stop_reason = "enemy_border";
                    continue;
                }
                if (preview_available_movement_half <
                    static_cast<std::int64_t>(preview_cost + cost) *
                        province::core::MovementSystem::movement_point_scale) {
                    preview_stop_reason = "insufficient_movement";
                    continue;
                }
                preview_cost += cost;
                ++preview_steps;
                preview_destination = path[index];
                preview_path_ids.push_back(godot::String::utf8(path[index].value().c_str()));
                if (army->advance_strategy == "one_step") {
                    preview_stop_reason = "strategy_limit";
                }
            }
        }
        response["accepted"] = true;
        response["path"] = path_ids;
        response["preview_path"] = preview_path_ids;
        response["step_count"] = static_cast<std::int64_t>(
            path.size() > 0 ? path.size() - 1 : 0
        );
        response["first_step_cost"] = first_step_cost;
        response["total_movement_cost"] = total_cost;
        response["preview_months"] = months;
        response["preview_movement_granted"] = movement_points_to_display(
            static_cast<std::int32_t>(movement_granted_half)
        );
        response["preview_available_movement"] = movement_points_to_display(
            static_cast<std::int32_t>(preview_available_movement_half)
        );
        response["preview_destination_id"] =
            godot::String::utf8(preview_destination.value().c_str());
        response["preview_step_count"] = preview_steps;
        response["preview_movement_cost"] = preview_cost;
        response["preview_stop_reason"] = godot::String::utf8(preview_stop_reason.c_str());
    } catch (const std::exception&) {
        set_stable_rejection(response, "army advance path could not be calculated");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "army advance target could not be set");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "army advance target could not be cleared");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "army advance setting could not be changed");
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
        if (strategy_value != "max" && strategy_value != "one_step" &&
            strategy_value != "stop_before_enemy") {
            response["accepted"] = false;
            response["error"] =
                "advance strategy must be 'max', 'one_step' or 'stop_before_enemy'";
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "army advance strategy could not be changed");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "war declaration could not be processed");
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
    } catch (const std::exception&) {
        set_stable_rejection(response, "peace settlement could not be processed");
    }
    return response;
}

} // namespace province::bridge
