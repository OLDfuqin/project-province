#include "province/core/command_processor.hpp"

#include <array>
#include <map>
#include <type_traits>
#include <variant>

namespace province::core {

CommandResult CommandProcessor::execute(GameState& state, const GameCommand& command) {
    return std::visit(
        [this, &state](const auto& concrete_command) -> CommandResult {
            using CommandType = std::decay_t<decltype(concrete_command)>;
            if constexpr (std::is_same_v<CommandType, AdvanceTurnCommand>) {
                return execute_advance_turn(state, concrete_command);
            }
        },
        command
    );
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

    // Intentionally tick one month at a time. Economy, population and AI
    // systems will be inserted inside this loop without changing commands.
    for (std::int32_t month = 0; month < command.months; ++month) {
        const MonthlyEconomyReport monthly_report = economy_system_.resolve_month(working_state);
        for (const CountryIncome& income : monthly_report.incomes) {
            total_income[income.country_id] += income.amount;
        }
        working_state.clock().advance_months(1);
    }

    std::vector<CountryIncome> incomes;
    incomes.reserve(total_income.size());
    for (const auto& [country_id, amount] : total_income) {
        incomes.push_back(CountryIncome{country_id, amount});
    }

    GameEvent economy_event{
        next_event_sequence_++,
        GameEventType::economy_resolved,
        EconomyResolvedEvent{command.months, std::move(incomes)},
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

    state = std::move(working_state);
    return CommandResult{true, {}, {std::move(economy_event), std::move(turn_event)}};
}

} // namespace province::core
