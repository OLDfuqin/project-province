#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <optional>
#include <vector>

namespace province::core {

struct ArmyBattleOutcome final {
    ArmyId army_id;
    std::int64_t casualties{};
    std::int64_t remaining_manpower{};
    std::optional<ProvinceId> retreat_province;
    bool destroyed{};
};

struct BattleResolution final {
    bool occurred{};
    ProvinceId province_id;
    CountryId attacker_id;
    CountryId defender_id;
    bool attacker_won{};
    bool province_occupied{};
    std::vector<ArmyBattleOutcome> armies;
};

class BattleSystem final {
public:
    [[nodiscard]] BattleResolution resolve_entry(
        GameState& state,
        const ArmyId& attacker_army_id,
        const ProvinceId& attacker_origin
    ) const;

private:
    [[nodiscard]] static std::optional<ProvinceId> find_retreat_province(
        const GameState& state,
        const CountryId& country_id,
        const ProvinceId& battle_province,
        const ProvinceId& excluded_province
    );
};

} // namespace province::core
