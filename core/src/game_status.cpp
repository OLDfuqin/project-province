#include "province/core/game_status.hpp"

namespace province::core {

GameStatus GameStatusSystem::evaluate(
    const GameState& state,
    const CountryId& player_country_id
) const {
    GameStatus status;
    for (const auto& [country_id, country] : state.countries()) {
        static_cast<void>(country);
        status.countries.emplace(country_id, CountryStatus{country_id, 0, true});
    }
    for (const auto& [province_id, province] : state.provinces()) {
        static_cast<void>(province);
        const CountryId controller = state.controller_of(province_id);
        auto entry = status.countries.find(controller);
        if (entry != status.countries.end()) {
            ++entry->second.controlled_provinces;
        }
    }

    std::optional<CountryId> last_survivor;
    std::int64_t survivor_count = 0;
    for (auto& [country_id, country_status] : status.countries) {
        country_status.eliminated = country_status.controlled_provinces == 0;
        if (!country_status.eliminated) {
            last_survivor = country_id;
            ++survivor_count;
        }
    }
    if (survivor_count == 1 && last_survivor.has_value()) {
        status.winner_id = last_survivor;
        status.game_over = true;
    }
    const auto player = status.countries.find(player_country_id);
    status.player_eliminated = player == status.countries.end() || player->second.eliminated;
    status.player_won = status.winner_id.has_value() && *status.winner_id == player_country_id;
    status.game_over = status.game_over || status.player_eliminated;
    return status;
}

} // namespace province::core
