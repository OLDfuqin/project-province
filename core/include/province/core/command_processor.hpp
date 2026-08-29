#pragma once

#include "province/core/army_system.hpp"
#include "province/core/ai_system.hpp"
#include "province/core/battle_system.hpp"
#include "province/core/game_command.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_state.hpp"
#include "province/core/population_system.hpp"
#include "province/core/peace_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/monthly_order_system.hpp"
#include "province/core/order_system.hpp"
#include "province/core/road_system.hpp"
#include "province/core/technology_system.hpp"

#include <cstdint>
#include <optional>
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
    CommandProcessor() = default;
    explicit CommandProcessor(BattleSystem::RandomRoll random_roll);

    [[nodiscard]] CommandResult execute(GameState& state, const GameCommand& command);
    [[nodiscard]] static bool is_supported_turn_length(std::int32_t months) noexcept;
    // Restore AI ownership when the loaded GameState already contains its orders.
    void enable_ai(CountryId human_country_id);
    // Initialize AI ownership for a new scenario and queue its first-month plan.
    void enable_ai(GameState& state, CountryId human_country_id);
    void disable_ai() noexcept;
    [[nodiscard]] bool ai_enabled() const noexcept;
    [[nodiscard]] const std::optional<CountryId>& human_country_id() const noexcept;
    [[nodiscard]] std::uint64_t next_event_sequence() const noexcept;
    void set_next_event_sequence(std::uint64_t sequence);
    [[nodiscard]] static constexpr std::uint64_t exhausted_event_sequence() noexcept {
        return province::core::exhausted_event_sequence;
    }

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
    [[nodiscard]] CommandResult execute_rename_army(
        GameState& state,
        const RenameArmyCommand& command
    );
    [[nodiscard]] CommandResult execute_merge_armies(
        GameState& state,
        const MergeArmiesCommand& command
    );
    [[nodiscard]] CommandResult execute_move_army(
        GameState& state,
        const MoveArmyCommand& command
    );
    [[nodiscard]] CommandResult execute_declare_war(
        GameState& state,
        const DeclareWarCommand& command
    );
    [[nodiscard]] CommandResult execute_make_peace(
        GameState& state,
        const MakePeaceCommand& command
    );
    [[nodiscard]] CommandResult execute_research_technology(
        GameState& state,
        const ResearchTechnologyCommand& command
    );
    [[nodiscard]] CommandResult execute_cancel_order(
        GameState& state,
        const CancelOrderCommand& command
    );
    [[nodiscard]] std::vector<GameEvent> queue_ai_orders(GameState& state);
    [[nodiscard]] std::uint64_t allocate_event_sequence();

    std::uint64_t next_event_sequence_{1};
    EconomySystem economy_system_;
    PopulationSystem population_system_;
    RoadSystem road_system_;
    ArmySystem army_system_;
    MovementSystem movement_system_;
    MonthlyOrderSystem monthly_order_system_;
    BattleSystem battle_system_;
    PeaceSystem peace_system_;
    AiSystem ai_system_;
    TechnologySystem technology_system_;
    OrderSystem order_system_;
    std::optional<CountryId> human_country_id_;
    bool ai_state_initialized_{};
};

} // namespace province::core
