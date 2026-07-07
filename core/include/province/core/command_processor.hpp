#pragma once

#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_state.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace province::core {

struct CommandResult final {
    bool accepted{};
    std::string error;
    std::vector<GameEvent> events;
};

class CommandProcessor final {
public:
    [[nodiscard]] CommandResult execute(GameState& state, const GameCommand& command);
    [[nodiscard]] static bool is_supported_turn_length(std::int32_t months) noexcept;

private:
    [[nodiscard]] CommandResult execute_advance_turn(
        GameState& state,
        const AdvanceTurnCommand& command
    );

    std::uint64_t next_event_sequence_{1};
};

} // namespace province::core

