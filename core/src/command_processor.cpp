#include "province/core/command_processor.hpp"

#include <array>
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

    // Intentionally tick one month at a time. Economy, population and AI
    // systems will be inserted inside this loop without changing commands.
    for (std::int32_t month = 0; month < command.months; ++month) {
        state.clock().advance_months(1);
    }

    GameEvent event{
        next_event_sequence_++,
        GameEventType::turn_advanced,
        TurnAdvancedEvent{
            previous_year,
            previous_month,
            state.clock().year(),
            state.clock().month(),
            command.months,
        },
    };

    return CommandResult{true, {}, {event}};
}

} // namespace province::core

