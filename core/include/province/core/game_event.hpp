#pragma once

#include <cstdint>
#include <variant>

namespace province::core {

enum class GameEventType : std::uint8_t {
    turn_advanced,
};

struct TurnAdvancedEvent final {
    std::int32_t previous_year{};
    std::int32_t previous_month{};
    std::int32_t current_year{};
    std::int32_t current_month{};
    std::int32_t elapsed_months{};
};

using GameEventPayload = std::variant<TurnAdvancedEvent>;

struct GameEvent final {
    std::uint64_t sequence{};
    GameEventType type{};
    GameEventPayload payload;
};

} // namespace province::core

