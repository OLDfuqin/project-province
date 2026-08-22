#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <vector>

namespace province::core {

enum class BattleResultType : std::uint8_t {
    defender_victory,
    attacker_victory,
    mutual_destruction,
};

struct DefenderBattleInput final {
    ArmyId army_id;
    CountryId country_id;
    std::int64_t manpower{};
    std::int32_t military_level{};
};

struct DefenderBattleLoss final {
    ArmyId army_id;
    std::int64_t casualties{};
    std::int64_t remaining_manpower{};
};

struct BattleCalculationInput final {
    std::int64_t attacker_manpower{};
    std::int32_t attacker_military_level{};
    std::vector<DefenderBattleInput> defenders;
    std::int32_t terrain_defense_bonus{};
    std::int32_t attacker_random_tenths{};
    std::int32_t defender_random_tenths{};
};

struct BattleCalculation final {
    BattleResultType result{BattleResultType::defender_victory};
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
    std::vector<DefenderBattleLoss> defender_losses;
};

class BattleCalculator final {
public:
    [[nodiscard]] static BattleCalculation calculate(
        const BattleCalculationInput& input
    );
};

} // namespace province::core
