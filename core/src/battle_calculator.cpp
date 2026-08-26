#include "province/core/battle_calculator.hpp"

#include <algorithm>
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

struct WideUnsigned final {
    std::uint64_t high{};
    std::uint64_t low{};
};

struct WideProduct final {
    std::uint64_t low{};
    std::uint64_t middle{};
    std::uint64_t high{};
};

struct DoubleWord final {
    std::uint64_t low{};
    std::uint64_t high{};
};

DoubleWord multiply_words(const std::uint64_t left, const std::uint64_t right) {
    const std::uint64_t left_low = static_cast<std::uint32_t>(left);
    const std::uint64_t left_high = left >> 32;
    const std::uint64_t right_low = static_cast<std::uint32_t>(right);
    const std::uint64_t right_high = right >> 32;

    const std::uint64_t low_product = left_low * right_low;
    const std::uint64_t cross_left = left_high * right_low;
    const std::uint64_t cross_right = left_low * right_high;
    const std::uint64_t high_product = left_high * right_high;
    const std::uint64_t middle =
        (low_product >> 32) +
        static_cast<std::uint32_t>(cross_left) +
        static_cast<std::uint32_t>(cross_right);

    return {
        (middle << 32) | static_cast<std::uint32_t>(low_product),
        high_product + (cross_left >> 32) + (cross_right >> 32) + (middle >> 32),
    };
}

void multiply(WideProduct& value, const std::uint64_t multiplier) {
    const std::uint64_t limbs[]{value.low, value.middle, value.high};
    std::uint64_t result[3]{};
    std::uint64_t carry = 0;
    for (std::size_t index = 0; index < 3; ++index) {
        const DoubleWord product = multiply_words(limbs[index], multiplier);
        result[index] = product.low + carry;
        const bool carry_from_addition = result[index] < product.low;
        carry = product.high + static_cast<std::uint64_t>(carry_from_addition);
    }
    if (carry != 0) {
        throw std::overflow_error{"wide integer multiplication overflowed"};
    }
    value = {result[0], result[1], result[2]};
}

WideProduct product_of(
    const std::uint64_t first,
    const std::uint64_t second,
    const std::uint64_t third,
    const std::uint64_t fourth = 1
) {
    WideProduct product{1, 0, 0};
    multiply(product, first);
    multiply(product, second);
    multiply(product, third);
    multiply(product, fourth);
    return product;
}

bool greater_or_equal(const WideProduct& left, const WideProduct& right) {
    if (left.high != right.high) {
        return left.high > right.high;
    }
    if (left.middle != right.middle) {
        return left.middle > right.middle;
    }
    return left.low >= right.low;
}

void add(WideUnsigned& value, const std::uint64_t addend) {
    const std::uint64_t previous_low = value.low;
    value.low += addend;
    if (value.low < previous_low) {
        if (value.high == std::numeric_limits<std::uint64_t>::max()) {
            throw std::overflow_error{"wide integer addition overflowed"};
        }
        ++value.high;
    }
}

bool greater_or_equal(const WideUnsigned& left, const WideUnsigned& right) {
    return left.high > right.high ||
        (left.high == right.high && left.low >= right.low);
}

void subtract(WideUnsigned& value, const WideUnsigned& subtrahend) {
    const bool borrow = value.low < subtrahend.low;
    value.low -= subtrahend.low;
    value.high -= subtrahend.high + static_cast<std::uint64_t>(borrow);
}

std::int32_t exact_weighted_level(
    const std::vector<DefenderBattleInput>& defenders,
    const std::int64_t total_manpower
) {
    WideUnsigned weighted_sum;
    for (const DefenderBattleInput& defender : defenders) {
        for (std::int32_t level = 0; level < defender.military_level; ++level) {
            add(weighted_sum, static_cast<std::uint64_t>(defender.manpower));
        }
    }

    const WideUnsigned divisor{0, static_cast<std::uint64_t>(total_manpower)};
    std::int32_t quotient = 0;
    while (greater_or_equal(weighted_sum, divisor)) {
        subtract(weighted_sum, divisor);
        ++quotient;
    }
    return quotient;
}

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
    return bonus == 0 || bonus == 10 || bonus == 20 || bonus == 30 || bonus == 50;
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

std::int64_t checked_multiply(
    const std::int64_t left,
    const std::int64_t right,
    const char* description
) {
    if (left != 0 && right > std::numeric_limits<std::int64_t>::max() / left) {
        throw std::overflow_error{description};
    }
    return left * right;
}

std::int64_t checked_strength_add(
    const std::int64_t left,
    const std::int64_t right,
    const char* description
) {
    if (right > std::numeric_limits<std::int64_t>::max() - left) {
        throw std::overflow_error{description};
    }
    return left + right;
}

std::int64_t scale_and_floor(
    const std::int64_t value,
    const std::int64_t numerator,
    const std::int64_t denominator,
    const char* description
) {
    const std::int64_t whole = checked_multiply(
        value / denominator,
        numerator,
        description
    );
    const std::int64_t fractional = checked_multiply(
        value % denominator,
        numerator,
        description
    ) / denominator;
    return checked_strength_add(whole, fractional, description);
}

std::int64_t greater_side_strength(
    const std::int64_t lesser,
    const std::int64_t greater,
    const std::uint64_t coefficient
) {
    const WideProduct strength_squared = product_of(
        coefficient,
        coefficient,
        static_cast<std::uint64_t>(lesser),
        static_cast<std::uint64_t>(greater)
    );
    constexpr std::uint64_t exclusive_limit = std::uint64_t{1} << 63;
    const WideProduct limit_squared = product_of(
        exclusive_limit,
        exclusive_limit,
        1'000'000
    );
    if (greater_or_equal(strength_squared, limit_squared)) {
        throw std::overflow_error{"battle strength exceeds int64 range"};
    }

    std::uint64_t lower = 0;
    std::uint64_t upper = exclusive_limit;
    while (lower + 1 < upper) {
        const std::uint64_t middle = lower + (upper - lower) / 2;
        const WideProduct candidate_squared = product_of(
            middle,
            middle,
            1'000'000
        );
        if (greater_or_equal(strength_squared, candidate_squared)) {
            lower = middle;
        } else {
            upper = middle;
        }
    }
    return static_cast<std::int64_t>(lower);
}

std::int64_t effective_strength(
    const std::int64_t lesser,
    const std::int64_t greater,
    const bool is_greater_side,
    const std::int32_t random_tenths,
    const std::int32_t military_level
) {
    const std::int64_t coefficient =
        random_tenths * (100 + 10 * military_level);
    if (!is_greater_side) {
        return scale_and_floor(
            lesser,
            coefficient,
            1'000,
            "battle strength exceeds int64 range"
        );
    }
    return greater_side_strength(
        lesser,
        greater,
        static_cast<std::uint64_t>(coefficient)
    );
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

template <typename Input, typename Loss>
std::vector<Loss> allocate_losses(
    const std::vector<Input>& participants,
    const std::int64_t total_manpower,
    const std::int64_t total_casualties
) {
    std::vector<Loss> losses;
    losses.reserve(participants.size());
    std::vector<std::int64_t> remainders;
    remainders.reserve(participants.size());

    std::int64_t assigned_casualties = 0;
    for (const Input& participant : participants) {
        const ProportionalShare share = proportional_share(
            total_casualties,
            participant.manpower,
            total_manpower
        );
        losses.push_back({
            participant.army_id,
            share.quotient,
            participant.manpower - share.quotient,
        });
        remainders.push_back(share.remainder);
        assigned_casualties += share.quotient;
    }

    std::vector<std::size_t> remainder_order(participants.size());
    std::iota(remainder_order.begin(), remainder_order.end(), std::size_t{0});
    std::sort(
        remainder_order.begin(),
        remainder_order.end(),
        [&remainders, &participants](const std::size_t left, const std::size_t right) {
            if (remainders[left] != remainders[right]) {
                return remainders[left] > remainders[right];
            }
            return participants[left].army_id < participants[right].army_id;
        }
    );

    const std::int64_t unassigned = total_casualties - assigned_casualties;
    for (std::int64_t index = 0; index < unassigned; ++index) {
        Loss& loss = losses[remainder_order[static_cast<std::size_t>(index)]];
        ++loss.casualties;
        --loss.remaining_manpower;
    }
    return losses;
}

} // namespace

BattleCalculation BattleCalculator::calculate(const BattleCalculationInput& input) {
    if (input.attackers.empty()) {
        throw std::invalid_argument{"battle requires at least one attacker"};
    }
    if (input.defenders.empty()) {
        throw std::invalid_argument{"battle requires at least one defender"};
    }
    validate_level(input.attacker_military_level);
    validate_roll(input.attacker_random_tenths);
    validate_roll(input.defender_random_tenths);
    if (!valid_terrain_bonus(input.terrain_defense_bonus)) {
        throw std::invalid_argument{"terrain defense bonus must be 0, 10, 20, 30, or 50"};
    }

    std::set<ArmyId> army_ids;
    std::int64_t attacker_manpower = 0;
    for (const AttackerBattleInput& attacker : input.attackers) {
        if (attacker.manpower <= 0) {
            throw std::invalid_argument{"attacker manpower must be positive"};
        }
        if (!army_ids.insert(attacker.army_id).second) {
            throw std::invalid_argument{"attacker army IDs must be unique"};
        }
        attacker_manpower = checked_add(
            attacker_manpower,
            attacker.manpower,
            "total attacker manpower exceeds int64 range"
        );
    }

    std::int64_t defender_manpower = 0;
    for (const DefenderBattleInput& defender : input.defenders) {
        if (defender.manpower <= 0) {
            throw std::invalid_argument{"defender manpower must be positive"};
        }
        validate_level(defender.military_level);
        if (!army_ids.insert(defender.army_id).second) {
            throw std::invalid_argument{"battle army IDs must be unique"};
        }
        defender_manpower = checked_add(
            defender_manpower,
            defender.manpower,
            "total defender manpower exceeds int64 range"
        );
    }

    const std::int32_t defender_military_level =
        exact_weighted_level(input.defenders, defender_manpower);
    const std::int64_t lesser = std::min(attacker_manpower, defender_manpower);
    const std::int64_t greater = std::max(attacker_manpower, defender_manpower);
    const std::int64_t attacker_base_strength = effective_strength(
        lesser,
        greater,
        attacker_manpower > defender_manpower,
        input.attacker_random_tenths,
        input.attacker_military_level
    );
    const std::int64_t defender_base_strength = effective_strength(
        lesser,
        greater,
        defender_manpower > attacker_manpower,
        input.defender_random_tenths,
        defender_military_level
    );
    const std::int64_t defender_final_strength = scale_and_floor(
        defender_base_strength,
        100 + input.terrain_defense_bonus,
        100,
        "terrain-adjusted defender strength exceeds int64 range"
    );

    const std::int64_t attacker_casualties = std::min(
        attacker_manpower,
        std::max<std::int64_t>(1, defender_final_strength / 2)
    );
    const std::int64_t defender_casualties = std::min(
        defender_manpower,
        std::max<std::int64_t>(1, attacker_base_strength / 2)
    );
    const std::int64_t attacker_remaining =
        attacker_manpower - attacker_casualties;
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
        attacker_manpower,
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
        allocate_losses<AttackerBattleInput, AttackerBattleLoss>(
            input.attackers,
            attacker_manpower,
            attacker_casualties
        ),
        allocate_losses<DefenderBattleInput, DefenderBattleLoss>(
            input.defenders,
            defender_manpower,
            defender_casualties
        ),
    };
}

} // namespace province::core
