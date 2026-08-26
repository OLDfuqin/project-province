#pragma once

#include "province/core/battle_calculator.hpp"
#include "province/core/game_state.hpp"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace province::core {

struct ArmyBattleOutcome final {
    ArmyId army_id;
    std::string display_name;
    std::int64_t casualties{};
    std::int64_t remaining_manpower{};
    std::optional<ProvinceId> retreat_province;
    bool destroyed{};
};

struct AttackingArmyEntry final {
    ArmyId army_id;
    ProvinceId origin;
};

struct BattleResolution final {
    bool occurred{};
    ProvinceId province_id;
    CountryId attacker_id;
    CountryId defender_id;
    BattleResultType result{BattleResultType::defender_victory};
    bool attacker_won{};
    bool province_occupied{};
    std::int32_t attacker_random_tenths{};
    std::int32_t defender_random_tenths{};
    std::int64_t attacker_initial_manpower{};
    std::int64_t defender_initial_manpower{};
    std::int32_t attacker_military_level{};
    std::int32_t defender_military_level{};
    std::int32_t terrain_defense_bonus{};
    std::int64_t attacker_base_strength{};
    std::int64_t defender_base_strength{};
    std::int64_t defender_final_strength{};
    std::int64_t attacker_casualties{};
    std::int64_t defender_casualties{};
    std::int64_t attacker_remaining_manpower{};
    std::int64_t defender_remaining_manpower{};
    std::vector<ArmyBattleOutcome> armies;
};

class BattleSystem final {
public:
    using RandomRoll = std::function<std::int32_t()>;

    explicit BattleSystem(RandomRoll random_roll = {});

    [[nodiscard]] BattleResolution resolve_entry(
        GameState& state,
        const ArmyId& attacker_army_id,
        const ProvinceId& attacker_origin
    ) const;
    [[nodiscard]] BattleResolution resolve_group(
        GameState& state,
        std::vector<AttackingArmyEntry> attackers
    ) const;

private:
    RandomRoll random_roll_;
};

} // namespace province::core
