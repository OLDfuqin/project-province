#pragma once

#include "province/core/game_state.hpp"

#include <map>
#include <optional>

namespace province::core {

struct CountryStatus final {
    CountryId country_id;
    std::int64_t controlled_provinces{};
    bool eliminated{};
};

struct GameStatus final {
    std::map<CountryId, CountryStatus> countries;
    std::optional<CountryId> winner_id;
    bool game_over{};
    bool player_eliminated{};
    bool player_won{};
};

class GameStatusSystem final {
public:
    [[nodiscard]] GameStatus evaluate(
        const GameState& state,
        const CountryId& player_country_id
    ) const;
};

} // namespace province::core
