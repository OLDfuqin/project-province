#pragma once

#include "province/core/economy_system.hpp"
#include "province/core/population_system.hpp"

#include <cstdint>
#include <variant>

namespace province::core {

enum class GameEventType : std::uint8_t {
    economy_resolved,
    population_resolved,
    turn_advanced,
};

struct TurnAdvancedEvent final {
    std::int32_t previous_year{};
    std::int32_t previous_month{};
    std::int32_t current_year{};
    std::int32_t current_month{};
    std::int32_t elapsed_months{};
};

struct EconomyResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<CountryIncome> incomes;
};

struct PopulationResolvedEvent final {
    std::int32_t elapsed_months{};
    std::vector<ProvincePopulationChange> changes;
};

using GameEventPayload =
    std::variant<EconomyResolvedEvent, PopulationResolvedEvent, TurnAdvancedEvent>;

struct GameEvent final {
    std::uint64_t sequence{};
    GameEventType type{};
    GameEventPayload payload;
};

} // namespace province::core
