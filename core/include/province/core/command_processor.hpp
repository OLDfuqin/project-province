#pragma once

#include "province/core/army_system.hpp"
#include "province/core/game_command.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_state.hpp"
#include "province/core/population_system.hpp"
#include "province/core/road_system.hpp"

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
    [[nodiscard]] CommandResult execute_build_road(
        GameState& state,
        const BuildRoadCommand& command
    );
    [[nodiscard]] CommandResult execute_recruit_army(
        GameState& state,
        const RecruitArmyCommand& command
    );

    std::uint64_t next_event_sequence_{1};
    EconomySystem economy_system_;
    PopulationSystem population_system_;
    RoadSystem road_system_;
    ArmySystem army_system_;
};

} // namespace province::core
