#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <filesystem>
#include <optional>
#include <stdexcept>

namespace province::core {

class SaveGameError final : public std::runtime_error {
public:
    explicit SaveGameError(const std::string& message);
};

struct LoadedGame final {
    GameState state;
    std::uint64_t next_event_sequence{1};
    CountryId player_country_id;
    std::optional<CountryId> ai_human_country_id;
};

class SaveGameSerializer final {
public:
    static constexpr std::int32_t schema_version = 7;

    static void save(
        const std::filesystem::path& path,
        const GameState& state,
        std::uint64_t next_event_sequence,
        const CountryId& player_country_id,
        const std::optional<CountryId>& ai_human_country_id
    );
    [[nodiscard]] static LoadedGame load(const std::filesystem::path& path);
};

} // namespace province::core
