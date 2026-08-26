#include "province/core/command_processor.hpp"
#include "province/core/maintenance_system.hpp"

#include <map>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <variant>

namespace province::core {

CommandProcessor::CommandProcessor(BattleSystem::RandomRoll random_roll)
    : battle_system_(std::move(random_roll)) {}

void CommandProcessor::enable_ai(CountryId human_country_id) {
    human_country_id_ = std::move(human_country_id);
}

void CommandProcessor::enable_ai(GameState& state, CountryId human_country_id) {
    enable_ai(std::move(human_country_id));
    static_cast<void>(queue_ai_orders(state));
}

void CommandProcessor::disable_ai() noexcept {
    human_country_id_.reset();
}

bool CommandProcessor::ai_enabled() const noexcept {
    return human_country_id_.has_value();
}

const std::optional<CountryId>& CommandProcessor::human_country_id() const noexcept {
    return human_country_id_;
}

std::uint64_t CommandProcessor::next_event_sequence() const noexcept {
    return next_event_sequence_;
}

void CommandProcessor::set_next_event_sequence(const std::uint64_t sequence) {
    if (sequence == 0) {
        throw std::invalid_argument{"event sequence must be positive"};
    }
    next_event_sequence_ = sequence;
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
            } else if constexpr (std::is_same_v<CommandType, RenameArmyCommand>) {
                return execute_rename_army(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, MergeArmiesCommand>) {
                return execute_merge_armies(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, MoveArmyCommand>) {
                return execute_move_army(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, DeclareWarCommand>) {
                return execute_declare_war(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, MakePeaceCommand>) {
                return execute_make_peace(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, ResearchTechnologyCommand>) {
                return execute_research_technology(state, concrete_command);
            } else if constexpr (std::is_same_v<CommandType, CancelOrderCommand>) {
                return execute_cancel_order(state, concrete_command);
            }
        },
        command
    );
}

CommandResult CommandProcessor::execute_rename_army(
    GameState& state,
    const RenameArmyCommand& command
) {
    GameState working_state = state;
    const ArmyRenameResult renamed = army_system_.rename(
        working_state,
        command.army_id,
        command.formation_number
    );
    if (!renamed.accepted) {
        return {false, renamed.error, {}};
    }
    GameEvent event{
        next_event_sequence_++,
        GameEventType::army_renamed,
        ArmyRenamedEvent{
            command.army_id,
            renamed.country_id,
            renamed.previous_formation_number,
            renamed.current_formation_number,
        },
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_merge_armies(
    GameState& state,
    const MergeArmiesCommand& command
) {
    GameState working_state = state;
    const ArmyMergeResult merged = army_system_.merge(
        working_state,
        command.primary_army_id,
        command.merged_army_ids
    );
    if (!merged.accepted) {
        return {false, merged.error, {}};
    }
    GameEvent event{
        next_event_sequence_++,
        GameEventType::armies_merged,
        ArmiesMergedEvent{
            command.primary_army_id,
            command.merged_army_ids,
            merged.previous_manpower,
            merged.current_manpower,
            merged.current_movement_points,
        },
    };
    state = std::move(working_state);
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_research_technology(
    GameState& state,
    const ResearchTechnologyCommand& command
) {
    const OrderOperationResult queued = order_system_.queue_research(
        state,
        command.country_id,
        command.track
    );
    if (!queued.accepted || !queued.order_id.has_value()) {
        return {false, queued.error, {}};
    }
    GameEvent event{
        next_event_sequence_++,
        GameEventType::order_created,
        OrderCreatedEvent{*queued.order_id},
    };
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_cancel_order(
    GameState& state,
    const CancelOrderCommand& command
) {
    const OrderOperationResult cancelled = order_system_.cancel(state, command.order_id);
    if (!cancelled.accepted) return {false, cancelled.error, {}};
    GameEvent event{
        next_event_sequence_++,
        GameEventType::order_cancelled,
        OrderCancelledEvent{command.order_id},
    };
    return {true, {}, {std::move(event)}};
}

std::vector<GameEvent> CommandProcessor::queue_ai_orders(GameState& state) {
    std::vector<GameEvent> events;
    if (!human_country_id_.has_value()) return events;

    const std::vector<AiDecision> decisions =
        ai_system_.plan_month(state, *human_country_id_);
    for (const AiDecision& decision : decisions) {
        const CommandResult result = execute(state, decision.command);
        if (!result.accepted) continue;
        for (const GameEvent& event : result.events) {
            if (event.type != GameEventType::order_created) {
                events.push_back(event);
            }
        }
    }
    return events;
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
    if (state.find_country(command.aggressor_id)->hidden ||
        state.find_country(command.defender_id)->hidden) {
        return {false, "hidden neutral country cannot participate in diplomacy", {}};
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
    const OrderOperationResult queued = order_system_.queue_road_construction(
        state,
        command.country_id,
        command.province_a,
        command.province_b
    );
    if (!queued.accepted || !queued.order_id.has_value()) {
        return {false, queued.error, {}};
    }

    GameEvent event{
        next_event_sequence_++,
        GameEventType::order_created,
        OrderCreatedEvent{*queued.order_id},
    };
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_recruit_army(
    GameState& state,
    const RecruitArmyCommand& command
) {
    const OrderOperationResult queued = order_system_.queue_recruitment(
        state,
        command.country_id,
        command.province_id,
        command.manpower
    );
    if (!queued.accepted || !queued.order_id.has_value()) {
        return {false, queued.error, {}};
    }

    GameEvent event{
        next_event_sequence_++,
        GameEventType::order_created,
        OrderCreatedEvent{*queued.order_id},
    };
    return {true, {}, {std::move(event)}};
}

CommandResult CommandProcessor::execute_move_army(
    GameState& state,
    const MoveArmyCommand& command
) {
    const Army* army = state.find_army(command.army_id);
    if (army == nullptr) {
        return {false, "ordered army does not exist", {}};
    }
    const std::vector<ProvinceId> path = movement_system_.find_order_path(
        state,
        command.army_id,
        command.destination
    );
    if (path.empty()) {
        return {false, "army destination is not reachable with available movement", {}};
    }
    const bool is_attack = state.controller_of(command.destination) != army->owner_id;
    const OrderOperationResult queued = order_system_.queue_army_action(
        state,
        command.army_id,
        path,
        is_attack
    );
    if (!queued.accepted || !queued.order_id.has_value()) {
        return {false, queued.error, {}};
    }
    GameEvent event{
        next_event_sequence_++,
        GameEventType::order_created,
        OrderCreatedEvent{*queued.order_id},
    };
    return {true, {}, {std::move(event)}};
}

bool CommandProcessor::is_supported_turn_length(const std::int32_t months) noexcept {
    return months == 1;
}

CommandResult CommandProcessor::execute_advance_turn(
    GameState& state,
    const AdvanceTurnCommand& command
) {
    if (!is_supported_turn_length(command.months)) {
        return CommandResult{
            false,
            "turn length must be exactly 1 month",
            {},
        };
    }

    const std::int32_t previous_year = state.clock().year();
    const std::int32_t previous_month = state.clock().month();
    GameState working_state = state;
    std::map<CountryId, std::int64_t> total_income;
    std::map<CountryId, std::int64_t> total_maintenance;
    std::map<ProvinceId, ProvincePopulationChange> population_changes;
    std::map<ArmyId, ArmyMovementGrant> movement_grants;
    std::vector<GameEvent> ai_events;

    // Intentionally tick one month at a time so every month observes state
    // changes produced by all preceding monthly systems.
    for (std::int32_t month = 0; month < command.months; ++month) {
        const MonthlyFiscalReport monthly_report = economy_system_.resolve_month(working_state);
        for (const CountryFiscalIncome& income : monthly_report.fiscal_incomes) {
            total_income[income.country_id] += income.amount;
        }
        const MonthlyMaintenanceReport maintenance_report =
            MaintenanceSystem{}.resolve_month(working_state);
        for (const CountryMaintenanceCharge& charge : maintenance_report.charges) {
            total_maintenance[charge.country_id] += charge.amount;
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
                existing->second.current_recruitable_population =
                    change.current_recruitable_population;
                existing->second.recruitable_growth += change.recruitable_growth;
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

        const MonthlyOrderMovementReport order_movement_report =
            monthly_order_system_.resolve_movement(working_state);
        for (const ResolvedArmyMovement& movement : order_movement_report.movements) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::army_moved,
                ArmyMovedEvent{
                    movement.army_id,
                    movement.origin,
                    movement.destination,
                    movement.movement_cost_half / MovementSystem::movement_point_scale,
                    movement.remaining_movement_half,
                },
            });
        }
        for (const RefundedArmyAction& refund : order_movement_report.refunds) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::order_cancelled,
                OrderCancelledEvent{refund.order_id},
            });
        }

        const MonthlyOrderCombatReport order_combat_report =
            monthly_order_system_.resolve_combat(working_state, battle_system_);
        for (const BattleResolution& battle : order_combat_report.battles) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::battle_resolved,
                battle,
            });
        }
        for (const RefundedArmyAction& refund : order_combat_report.refunds) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::order_cancelled,
                OrderCancelledEvent{refund.order_id},
            });
        }

        const MonthlyOrderProjectReport project_report =
            monthly_order_system_.resolve_projects(working_state);
        for (const CompletedRecruitmentOrder& recruitment : project_report.recruitments) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::army_recruited,
                ArmyRecruitedEvent{
                    recruitment.army_id,
                    recruitment.country_id,
                    recruitment.province_id,
                    recruitment.manpower,
                    recruitment.paid_cost,
                },
            });
        }
        for (const CompletedRoadOrder& road : project_report.roads) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::road_built,
                RoadBuiltEvent{
                    road.country_id,
                    road.province_a,
                    road.province_b,
                    RoadLevel::paved,
                    road.paid_cost,
                },
            });
        }
        for (const CompletedResearchOrder& research : project_report.research) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::technology_researched,
                research.result,
            });
        }
        for (const RefundedProjectOrder& refund : project_report.refunds) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::order_cancelled,
                OrderCancelledEvent{refund.order_id},
            });
        }

        const MonthlyArmyConsolidationReport consolidation_report =
            monthly_order_system_.consolidate_armies(working_state);
        for (const AutomaticArmyMerge& merge : consolidation_report.merges) {
            ai_events.push_back(GameEvent{
                next_event_sequence_++,
                GameEventType::armies_merged,
                ArmiesMergedEvent{
                    merge.primary_army_id,
                    merge.merged_army_ids,
                    merge.previous_manpower,
                    merge.current_manpower,
                    merge.current_movement_points,
                },
            });
        }

        std::vector<ArmyId> planned_armies;
        planned_armies.reserve(working_state.army_count());
        for (const auto& [army_id, army] : working_state.armies()) {
            if (army.advance_target.has_value() && army.advance_enabled) {
                planned_armies.push_back(army_id);
            }
        }
        for (const ArmyId& army_id : planned_armies) {
            const Army* army = working_state.find_army(army_id);
            if (army == nullptr || !army->advance_target.has_value() ||
                !army->advance_enabled) {
                continue;
            }
            const std::optional<ProvinceId> next_step = ai_system_.find_step_toward(
                working_state,
                *army,
                *army->advance_target
            );
            if (!next_step.has_value()) {
                continue;
            }
            if (army->advance_strategy == "stop_before_enemy" &&
                working_state.controller_of(*next_step) != army->owner_id) {
                continue;
            }
            const CommandResult move_result = execute(
                working_state,
                MoveArmyCommand{army_id, *next_step}
            );
            if (move_result.accepted) {
                ai_events.insert(
                    ai_events.end(),
                    move_result.events.begin(),
                    move_result.events.end()
                );
            }
        }
        std::vector<GameEvent> planned_ai_events = queue_ai_orders(working_state);
        ai_events.insert(
            ai_events.end(),
            planned_ai_events.begin(),
            planned_ai_events.end()
        );
        working_state.clock().advance_months(1);
    }

    std::vector<CountryFiscalIncome> fiscal_incomes;
    fiscal_incomes.reserve(total_income.size());
    for (const auto& [country_id, amount] : total_income) {
        fiscal_incomes.push_back(CountryFiscalIncome{country_id, amount});
    }
    std::vector<CountryMaintenanceCharge> maintenance_charges;
    maintenance_charges.reserve(total_maintenance.size());
    for (const auto& [country_id, amount] : total_maintenance) {
        maintenance_charges.push_back(CountryMaintenanceCharge{country_id, amount});
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

    GameEvent fiscal_income_event{
        next_event_sequence_++,
        GameEventType::fiscal_income_resolved,
        FiscalIncomeResolvedEvent{command.months, std::move(fiscal_incomes)},
    };
    GameEvent maintenance_event{
        next_event_sequence_++,
        GameEventType::maintenance_resolved,
        MaintenanceResolvedEvent{command.months, std::move(maintenance_charges)},
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

    ai_events.push_back(std::move(fiscal_income_event));
    ai_events.push_back(std::move(maintenance_event));
    ai_events.push_back(std::move(population_event));
    ai_events.push_back(std::move(date_event));
    ai_events.push_back(std::move(turn_event));
    state = std::move(working_state);
    return CommandResult{true, {}, std::move(ai_events)};
}

} // namespace province::core
