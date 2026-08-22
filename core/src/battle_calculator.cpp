#include "province/core/battle_calculator.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <numeric>
#include <set>
#include <stdexcept>
#include <vector>

namespace province::core {

namespace {

struct ProportionalShare final {
    std::int64_t quotient{};
    std::int64_t remainder{};
};

void validate_level(const std::int32_t level) {
    if (level < 0 || level > 8) {
        throw std::invalid_argument{"military level must be in the range 0..8"};
    }
}

void validate_roll(const std::int32_t roll) {
    if (roll < 7 || roll > 14) {
        throw std::invalid_argument{"battle roll must be in the range 7..14"};
    }
}

bool valid_terrain_bonus(const std::int32_t bonus) {
    return bonus == 0 || bonus == 10 || bonus == 20 || bonus == 30;
}

std::int64_t checked_add(
    const std::int64_t left,
    const std::int64_t right,
    const char* description
) {
    if (right > std::numeric_limits<std::int64_t>::max() - left) {
        throw std::invalid_argument{description};
    }
    return left + right;
}

std::int64_t floor_strength(
    const long double strength,
    const char* description
) {
    if (!std::isfinite(strength) ||
        strength > static_cast<long double>(std::numeric_limits<std::int64_t>::max())) {
        throw std::overflow_error{description};
    }
    return static_cast<std::int64_t>(std::floor(strength));
}

std::int64_t effective_strength(
    const std::int64_t lesser,
    const std::int64_t greater,
    const bool is_greater_side,
    const std::int32_t random_tenths,
    const std::int32_t military_level
) {
    long double strength = static_cast<long double>(random_tenths) / 10.0L;
    strength *= static_cast<long double>(lesser);
    if (is_greater_side) {
        strength *= std::sqrt(
            static_cast<long double>(greater) / static_cast<long double>(lesser)
        );
    }
    strength *= static_cast<long double>(100 + 10 * military_level) / 100.0L;
    return floor_strength(strength, "battle strength exceeds int64 range");
}

ProportionalShare proportional_share(
    const std::int64_t casualties,
    const std::int64_t manpower,
    const std::int64_t total_manpower
) {
    const auto maximum = std::numeric_limits<std::int64_t>::max();
    if (casualties <= maximum / manpower) {
        const std::int64_t numerator = casualties * manpower;
        return {numerator / total_manpower, numerator % total_manpower};
    }

    const auto divisor = static_cast<std::uint64_t>(total_manpower);
    const auto addend = static_cast<std::uint64_t>(casualties);
    const auto multiplier = static_cast<std::uint64_t>(manpower);
    std::uint64_t quotient = 0;
    std::uint64_t remainder = 0;

    for (int bit = 62; bit >= 0; --bit) {
        quotient *= 2;

        const std::uint64_t doubled_remainder = remainder * 2;
        if (doubled_remainder >= divisor) {
            remainder = doubled_remainder - divisor;
            ++quotient;
        } else {
            remainder = doubled_remainder;
        }

        if ((multiplier & (std::uint64_t{1} << bit)) != 0) {
            const std::uint64_t increased_remainder = remainder + addend;
            if (increased_remainder >= divisor) {
                remainder = increased_remainder - divisor;
                ++quotient;
            } else {
                remainder = increased_remainder;
            }
        }
    }

    return {
        static_cast<std::int64_t>(quotient),
        static_cast<std::int64_t>(remainder),
    };
}

std::vector<DefenderBattleLoss> allocate_defender_losses(
    const std::vector<DefenderBattleInput>& defenders,
    const std::int64_t total_manpower,
    const std::int64_t total_casualties
) {
    std::vector<DefenderBattleLoss> losses;
    losses.reserve(defenders.size());
    std::vector<std::int64_t> remainders;
    remainders.reserve(defenders.size());

    std::int64_t assigned_casualties = 0;
    for (const DefenderBattleInput& defender : defenders) {
        const ProportionalShare share = proportional_share(
            total_casualties,
            defender.manpower,
            total_manpower
        );
        losses.push_back({
            defender.army_id,
            share.quotient,
            defender.manpower - share.quotient,
        });
        remainders.push_back(share.remainder);
        assigned_casualties += share.quotient;
    }

    std::vector<std::size_t> remainder_order(defenders.size());
    std::iota(remainder_order.begin(), remainder_order.end(), std::size_t{0});
    std::sort(
        remainder_order.begin(),
        remainder_order.end(),
        [&remainders, &defenders](const std::size_t left, const std::size_t right) {
            if (remainders[left] != remainders[right]) {
                return remainders[left] > remainders[right];
            }
            return defenders[left].army_id < defenders[right].army_id;
        }
    );

    const std::int64_t unassigned = total_casualties - assigned_casualties;
    for (std::int64_t index = 0; index < unassigned; ++index) {
        DefenderBattleLoss& loss = losses[remainder_order[static_cast<std::size_t>(index)]];
        ++loss.casualties;
        --loss.remaining_manpower;
    }
    return losses;
}

} // namespace

BattleCalculation BattleCalculator::calculate(const BattleCalculationInput& input) {
    if (input.attacker_manpower <= 0) {
        throw std::invalid_argument{"attacker manpower must be positive"};
    }
    if (input.defenders.empty()) {
        throw std::invalid_argument{"battle requires at least one defender"};
    }
    validate_level(input.attacker_military_level);
    validate_roll(input.attacker_random_tenths);
    validate_roll(input.defender_random_tenths);
    if (!valid_terrain_bonus(input.terrain_defense_bonus)) {
        throw std::invalid_argument{"terrain defense bonus must be 0, 10, 20, or 30"};
    }

    std::set<ArmyId> defender_ids;
    std::int64_t defender_manpower = 0;
    long double weighted_defender_levels = 0.0L;
    for (const DefenderBattleInput& defender : input.defenders) {
        if (defender.manpower <= 0) {
            throw std::invalid_argument{"defender manpower must be positive"};
        }
        validate_level(defender.military_level);
        if (!defender_ids.insert(defender.army_id).second) {
            throw std::invalid_argument{"defender army IDs must be unique"};
        }
        defender_manpower = checked_add(
            defender_manpower,
            defender.manpower,
            "total defender manpower exceeds int64 range"
        );
        weighted_defender_levels +=
            static_cast<long double>(defender.manpower) * defender.military_level;
    }

    const auto defender_military_level = static_cast<std::int32_t>(std::floor(
        weighted_defender_levels / static_cast<long double>(defender_manpower)
    ));
    const std::int64_t lesser = std::min(input.attacker_manpower, defender_manpower);
    const std::int64_t greater = std::max(input.attacker_manpower, defender_manpower);
    const std::int64_t attacker_base_strength = effective_strength(
        lesser,
        greater,
        input.attacker_manpower > defender_manpower,
        input.attacker_random_tenths,
        input.attacker_military_level
    );
    const std::int64_t defender_base_strength = effective_strength(
        lesser,
        greater,
        defender_manpower > input.attacker_manpower,
        input.defender_random_tenths,
        defender_military_level
    );
    const std::int64_t defender_final_strength = floor_strength(
        static_cast<long double>(defender_base_strength) *
            static_cast<long double>(100 + input.terrain_defense_bonus) / 100.0L,
        "terrain-adjusted defender strength exceeds int64 range"
    );

    const std::int64_t attacker_casualties = std::min(
        input.attacker_manpower,
        std::max<std::int64_t>(1, defender_final_strength / 2)
    );
    const std::int64_t defender_casualties = std::min(
        defender_manpower,
        std::max<std::int64_t>(1, attacker_base_strength / 2)
    );
    const std::int64_t attacker_remaining =
        input.attacker_manpower - attacker_casualties;
    const std::int64_t defender_remaining = defender_manpower - defender_casualties;

    BattleResultType result = BattleResultType::defender_victory;
    if (defender_remaining == 0) {
        result = attacker_remaining == 0
            ? BattleResultType::mutual_destruction
            : BattleResultType::attacker_victory;
    }

    return {
        result,
        input.attacker_random_tenths,
        input.defender_random_tenths,
        input.attacker_manpower,
        defender_manpower,
        input.attacker_military_level,
        defender_military_level,
        input.terrain_defense_bonus,
        attacker_base_strength,
        defender_base_strength,
        defender_final_strength,
        attacker_casualties,
        defender_casualties,
        attacker_remaining,
        defender_remaining,
        allocate_defender_losses(
            input.defenders,
            defender_manpower,
            defender_casualties
        ),
    };
}

} // namespace province::core
