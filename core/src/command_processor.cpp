#include "province/core/command_processor.hpp"

#include <array>
#include <map>
#include <type_traits>
#include <variant>

namespace province::core {

void CommandProcessor::enable_ai(CountryId human_country_id) {
    human_country_id_ = std::move(human_country_id);
}

void CommandProcessor::disable_ai() noexcept {
    human_country_id_.reset();
}

bool CommandProcessor::ai_enabled() const noexcept {
    return human_country_id_.has_value();
}

CommandResult CommandProcessor::execute(GameState& state, const GameCommand& command) {
    return std::visit(
        [this, &state](const auto& concrete_command) -> CommandResult {
            using CommandType = std::decay_t<decltype(concrete_command)>;
            if constexpr (std::is_same_v<CommandType, AdvanceTurnCommand>) {
                return execute_advance_turn(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, BuildRoadCommand>) {
                return execute_build_road(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, RecruitArmyCommand>) {
                return execute_recruit_army(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, MoveArmyCommand>) {
                return execute_move_army(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, DeclareWarCommand>) {
                return execute_declare_war(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, MakePeaceCommand>) {
                return execute_make_peace(state, concrete_command);
            }
        },
        command
    );
}

CommandResult CommandProcessor::execute_make_peace(
    GameState& state,
    const MakePeaceCommand& command
) {
    GameState working_state = state;
    PeaceSettlementResult settlement = peace_system_.settle(
        working_state,
        command.country_a,
        command.country_b,
        command.policy
    );
    if (!settlement.accepted) {
        return {false, settlement.error, {}};
    }
    GameEvent event{
        next_event_sequence_++,
        GameEventType::peace_made,
        settlement,
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_declare_war(
    GameState& state,
    const DeclareWarCommand& command
) {
    if (command.aggressor_id == command.defender_id) {
        return {false, "a country cannot declare war on itself", {}};
    }
    if (state.find_country(command.aggressor_id) == nullptr) {
        return {false, "aggressor country does not exist", {}};
    }
    if (state.find_country(command.defender_id) == nullptr) {
        return {false, "defender country does not exist", {}};
    }
    if (state.are_at_war(command.aggressor_id, command.defender_id)) {
        return {false, "countries are already at war", {}};
    }

    GameState working_state = state;
    working_state.set_diplomatic_status(
        command.aggressor_id,
        command.defender_id,
        DiplomaticStatus::war
    );
    GameEvent event{
        next_event_sequence_++,
        GameEventType::war_declared,
        WarDeclaredEvent{command.aggressor_id, command.defender_id},
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_build_road(
    GameState& state,
    const BuildRoadCommand& command
) {
    GameState working_state = state;
    const RoadBuildResult build = road_system_.build_paved_road(
        working_state,
        command.country_id,
        command.province_a,
        command.province_b
    );
    if (!build.accepted) {
        return {false, build.error, {}};
    }

    GameEvent event{
        next_event_sequence_++,
        GameEventType::road_built,
        RoadBuiltEvent{
            command.country_id,
            command.province_a,
            command.province_b,
            RoadLevel::paved,
            build.cost,
        },
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_recruit_army(
    GameState& state,
    const RecruitArmyCommand& command
) {
    GameState working_state = state;
    const ArmyRecruitResult recruit = army_system_.recruit(
        working_state,
        command.country_id,
        command.province_id,
        command.manpower
    );
    if (!recruit.accepted || !recruit.army_id.has_value()) {
        return {false, recruit.error, {}};
    }

    GameEvent event{
        next_event_sequence_++,
        GameEventType::army_recruited,
        ArmyRecruitedEvent{
            *recruit.army_id,
            command.country_id,
            command.province_id,
            command.manpower,
            recruit.cost,
        },
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_move_army(
    GameState& state,
    const MoveArmyCommand& command
) {
    GameState working_state = state;
    const ArmyMoveResult move = movement_system_.move(
        working_state,
        command.army_id,
        command.destination
    );
    if (!move.accepted) {
        return {false, move.error, {}};
    }

    const Army* army = working_state.find_army(command.army_id);
    if (army == nullptr) {
        return {false, "army disappeared after movement", {}};
    }
    GameEvent move_event{
        next_event_sequence_++,
        GameEventType::army_moved,
        ArmyMovedEvent{
            command.army_id,
            move.origin,
            move.destination,
            move.cost,
            army->movement_points,
        },
    };
    const BattleResolution battle = battle_system_.resolve_entry(
        working_state,
        command.army_id,
        move.origin
    );
    std::vector<GameEvent> events;
    events.push_back(std::move(move_event));
    if (battle.occurred || battle.province_occupied) {
        events.push_back(GameEvent{
            next_event_sequence_++,
            GameEventType::battle_resolved,
            battle,
        });
    }
    state = std::move(working_state);
    return {true, {}, std::move(events)};
}

bool CommandProcessor::is_supported_turn_length(const std::int32_t months) noexcept {
    constexpr std::array supported_lengths{1, 3, 6, 12};
    for (const std::int32_t supported : supported_lengths) {
        if (months == supported) {
            return true;
        }
    }
    return false;
}

CommandResult CommandProcessor::execute_advance_turn(
    GameState& state,
    const AdvanceTurnCommand& command
) {
    if (!is_supported_turn_length(command.months)) {
        return CommandResult{
            false,
            "turn length must be one of 1, 3, 6 or 12 months",
            {},
        };
    }

    const std::int32_t previous_year = state.clock().year();
    const std::int32_t previous_month = state.clock().month();
    GameState working_state = state;
    std::map<CountryId, std::int64_t> total_income;
    std::map<ProvinceId, ProvincePopulationChange> population_changes;
    std::map<ArmyId, ArmyMovementGrant> movement_grants;
    std::vector<GameEvent> ai_events;

    // Intentionally tick one month at a time. Economy, population and AI
    // systems will be inserted inside this loop without changing commands.
    for (std::int32_t month = 0; month < command.months; ++month) {
        const MonthlyEconomyReport monthly_report = economy_system_.resolve_month(working_state);
        for (const CountryIncome& income : monthly_report.incomes) {
            total_income[income.country_id] += income.amount;
        }
        const MonthlyPopulationReport population_report =
            population_system_.resolve_month(working_state);
        for (const ProvincePopulationChange& change : population_report.changes) {
            const auto existing = population_changes.find(change.province_id);
            if (existing == population_changes.end()) {
                population_changes.emplace(change.province_id, change);
            } else {
                existing->second.current_population = change.current_population;
                existing->second.growth += change.growth;
            }
        }
        const MonthlyMovementReport movement_report =
            movement_system_.grant_monthly_points(working_state);
        for (const ArmyMovementGrant& grant : movement_report.grants) {
            const auto existing = movement_grants.find(grant.army_id);
            if (existing == movement_grants.end()) {
                movement_grants.emplace(grant.army_id, grant);
            } else {
                existing->second.amount += grant.amount;
                existing->second.current_points = grant.current_points;
            }
        }
        if (human_country_id_.has_value()) {
            const std::vector<AiDecision> decisions =
                ai_system_.plan_month(working_state, *human_country_id_);
            for (const AiDecision& decision : decisions) {
                const CommandResult ai_result = execute(working_state, decision.command);
                if (ai_result.accepted) {
                    ai_events.insert(
                        ai_events.end(),
                        ai_result.events.begin(),
                        ai_result.events.end()
                    );
                }
            }
        }
        working_state.clock().advance_months(1);
    }

    std::vector<CountryIncome> incomes;
    incomes.reserve(total_income.size());
    for (const auto& [country_id, amount] : total_income) {
        incomes.push_back(CountryIncome{country_id, amount});
    }
    std::vector<ProvincePopulationChange> changes;
    changes.reserve(population_changes.size());
    for (const auto& [province_id, change] : population_changes) {
        static_cast<void>(province_id);
        changes.push_back(change);
    }
    std::vector<ArmyMovementGrant> grants;
    grants.reserve(movement_grants.size());
    for (const auto& [army_id, grant] : movement_grants) {
        static_cast<void>(army_id);
        grants.push_back(grant);
    }

    GameEvent economy_event{
        next_event_sequence_++,
        GameEventType::economy_resolved,
        EconomyResolvedEvent{command.months, std::move(incomes)},
    };
    GameEvent population_event{
        next_event_sequence_++,
        GameEventType::population_resolved,
        PopulationResolvedEvent{command.months, std::move(changes)},
    };
    GameEvent date_event{
        next_event_sequence_++,
        GameEventType::movement_points_granted,
        MovementPointsGrantedEvent{command.months, std::move(grants)},
    };
    GameEvent turn_event{
        next_event_sequence_++,
        GameEventType::turn_advanced,
        TurnAdvancedEvent{
            previous_year,
            previous_month,
            working_state.clock().year(),
            working_state.clock().month(),
            command.months,
        },
    };

    ai_events.push_back(std::move(economy_event));
    ai_events.push_back(std::move(population_event));
    ai_events.push_back(std::move(date_event));
    ai_events.push_back(std::move(turn_event));
    state = std::move(working_state);
    return CommandResult{true, {}, std::move(ai_events)};
}

} // namespace province::core
