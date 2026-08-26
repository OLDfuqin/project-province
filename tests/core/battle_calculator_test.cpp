#include "smoke_test_groups.hpp"

#include "province/core/battle_calculator.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <limits>
#include <stdexcept>

namespace {

bool expect(const bool condition, const char* message) {
    if (!condition) {
        std::cerr << "BattleCalculator test failed: " << message << '\n';
    }
    return condition;
}

bool expect_invalid(const province::core::BattleCalculationInput& input) {
    try {
        [[maybe_unused]] const auto result =
            province::core::BattleCalculator::calculate(input);
    } catch (const std::invalid_argument&) {
        return true;
    } catch (...) {
        return false;
    }
    return false;
}

bool expect_overflow(const province::core::BattleCalculationInput& input) {
    try {
        [[maybe_unused]] const auto result =
            province::core::BattleCalculator::calculate(input);
    } catch (const std::overflow_error&) {
        return true;
    } catch (...) {
        return false;
    }
    return false;
}

const province::core::DefenderBattleLoss* find_loss(
    const province::core::BattleCalculation& calculation,
    const province::core::ArmyId& army_id
) {
    const auto found = std::find_if(
        calculation.defender_losses.begin(),
        calculation.defender_losses.end(),
        [&army_id](const province::core::DefenderBattleLoss& loss) {
            return loss.army_id == army_id;
        }
    );
    return found == calculation.defender_losses.end() ? nullptr : &*found;
}

const province::core::AttackerBattleLoss* find_attacker_loss(
    const province::core::BattleCalculation& calculation,
    const province::core::ArmyId& army_id
) {
    const auto found = std::find_if(
        calculation.attacker_losses.begin(),
        calculation.attacker_losses.end(),
        [&army_id](const province::core::AttackerBattleLoss& loss) {
            return loss.army_id == army_id;
        }
    );
    return found == calculation.attacker_losses.end() ? nullptr : &*found;
}

} // namespace

bool run_battle_calculator_tests() {
    using province::core::ArmyId;
    using province::core::BattleCalculation;
    using province::core::BattleCalculationInput;
    using province::core::BattleCalculator;
    using province::core::BattleResultType;
    using province::core::CountryId;
    using province::core::DefenderBattleInput;

    const BattleCalculation grouped_tie = BattleCalculator::calculate({
        {
            {ArmyId{"attacker_z"}, 1},
            {ArmyId{"attacker_a"}, 1},
        },
        0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 2, 0}},
        0, 7, 7,
    });
    const auto* tied_a = find_attacker_loss(grouped_tie, ArmyId{"attacker_a"});
    const auto* tied_z = find_attacker_loss(grouped_tie, ArmyId{"attacker_z"});
    if (!expect(
            grouped_tie.attacker_initial_manpower == 2 &&
                grouped_tie.attacker_casualties == 1 &&
                grouped_tie.attacker_losses.size() == 2 &&
                tied_a != nullptr && tied_a->casualties == 1 &&
                tied_a->remaining_manpower == 0 &&
                tied_z != nullptr && tied_z->casualties == 0 &&
                tied_z->remaining_manpower == 1,
            "grouped attacker losses did not use stable IDs to break equal remainders"
        )) {
        return false;
    }

    const BattleCalculation grouped_unequal = BattleCalculator::calculate({
        {
            {ArmyId{"attacker_a"}, 2},
            {ArmyId{"attacker_z"}, 1},
        },
        0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 3, 0}},
        0, 7, 14,
    });
    const auto* larger = find_attacker_loss(grouped_unequal, ArmyId{"attacker_a"});
    const auto* smaller = find_attacker_loss(grouped_unequal, ArmyId{"attacker_z"});
    if (!expect(
            grouped_unequal.attacker_initial_manpower == 3 &&
                grouped_unequal.attacker_casualties == 2 &&
                larger != nullptr && larger->casualties == 1 &&
                smaller != nullptr && smaller->casualties == 1,
            "grouped attacker losses did not award the larger fractional remainder"
        )) {
        return false;
    }

    const BattleCalculation equal = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1'000}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
        0, 7, 14,
    });
    // Attacker strength 700; defender strength 1400.
    // Attacker loses 700 and defender loses 350: defender survives and wins.
    if (!expect(
            equal.result == BattleResultType::defender_victory &&
                equal.attacker_base_strength == 700 &&
                equal.defender_base_strength == 1'400 &&
                equal.defender_final_strength == 1'400 &&
                equal.attacker_casualties == 700 &&
                equal.defender_casualties == 350 &&
                equal.attacker_remaining_manpower == 300 &&
                equal.defender_remaining_manpower == 650 &&
                equal.defender_losses.size() == 1 &&
                equal.defender_losses.front().casualties == 350 &&
                equal.defender_losses.front().remaining_manpower == 650,
            "equal forces did not use independent fixed rolls"
        )) {
        return false;
    }

    const BattleCalculation larger_attacker = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 4'000}}, 2,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
        0, 10, 10,
    });
    // Attacker strength floor(1000 * sqrt(4) * 1.2) = 2400.
    // Defender strength 1000, so defender is destroyed and attacker survives.
    if (!expect(
            larger_attacker.result == BattleResultType::attacker_victory &&
                larger_attacker.attacker_base_strength == 2'400 &&
                larger_attacker.defender_base_strength == 1'000 &&
                larger_attacker.attacker_casualties == 500 &&
                larger_attacker.defender_casualties == 1'000 &&
                larger_attacker.attacker_remaining_manpower == 3'500 &&
                larger_attacker.defender_remaining_manpower == 0,
            "larger attacker strength or victory was incorrect"
        )) {
        return false;
    }

    const BattleCalculation mountain = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1'000}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
        30, 10, 10,
    });
    // Defender base strength 1000 and final terrain strength 1300.
    if (!expect(
            mountain.defender_base_strength == 1'000 &&
                mountain.defender_final_strength == 1'300,
            "mountain defense was not applied after base strength"
        )) {
        return false;
    }

    const BattleCalculation weighted = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 2'000}}, 0,
        {
            {ArmyId{"d1"}, CountryId{"solmere"}, 300, 2},
            {ArmyId{"d2"}, CountryId{"verdantia"}, 700, 5},
        },
        0, 10, 10,
    });
    // floor((300*2 + 700*5)/1000) = 4.
    if (!expect(
            weighted.defender_military_level == 4 &&
                weighted.defender_base_strength == 1'400,
            "weighted defender military level did not round down"
        )) {
        return false;
    }

    const BattleCalculation remainders = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 7}}, 0,
        {
            {ArmyId{"army_b"}, CountryId{"solmere"}, 1, 0},
            {ArmyId{"army_a"}, CountryId{"solmere"}, 1, 0},
            {ArmyId{"army_c"}, CountryId{"solmere"}, 1, 0},
        },
        0, 10, 10,
    });
    // Attacker strength floor(3*sqrt(7/3)) = 4; defender losses = 2.
    // Equal remainders award losses to army_a then army_b by stable ID.
    const auto* army_a_loss = find_loss(remainders, ArmyId{"army_a"});
    const auto* army_b_loss = find_loss(remainders, ArmyId{"army_b"});
    const auto* army_c_loss = find_loss(remainders, ArmyId{"army_c"});
    if (!expect(
            remainders.attacker_base_strength == 4 &&
                remainders.defender_casualties == 2 &&
                army_a_loss != nullptr && army_a_loss->casualties == 1 &&
                army_b_loss != nullptr && army_b_loss->casualties == 1 &&
                army_c_loss != nullptr && army_c_loss->casualties == 0,
            "largest-remainder ties were not resolved by stable army ID"
        )) {
        return false;
    }

    const BattleCalculation unequal_remainders = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1'000}}, 2,
        {
            {ArmyId{"army_a"}, CountryId{"solmere"}, 500, 1},
            {ArmyId{"army_z"}, CountryId{"verdantia"}, 300, 2},
        },
        20, 9, 11,
    });
    // Total losses are 482. Exact shares are 301.25 and 180.75, so army_z
    // receives the one unassigned casualty despite its lexically larger ID.
    const auto* smaller_remainder_loss = find_loss(
        unequal_remainders, ArmyId{"army_a"}
    );
    const auto* larger_remainder_loss = find_loss(
        unequal_remainders, ArmyId{"army_z"}
    );
    if (!expect(
            unequal_remainders.attacker_base_strength == 965 &&
                unequal_remainders.defender_casualties == 482 &&
                smaller_remainder_loss != nullptr &&
                smaller_remainder_loss->casualties == 301 &&
                larger_remainder_loss != nullptr &&
                larger_remainder_loss->casualties == 181,
            "the larger unequal remainder did not receive the extra casualty"
        )) {
        return false;
    }

    const BattleCalculation mutual = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 1, 0}},
        0, 7, 7,
    });
    if (mutual.result != BattleResultType::mutual_destruction ||
        mutual.attacker_remaining_manpower != 0 ||
        mutual.defender_remaining_manpower != 0) return false;

    const BattleCalculationInput valid{
        {{ArmyId{"attacker"}, 1'000}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, 1'000, 0}},
        0, 10, 10,
    };
    BattleCalculationInput zero_attacker = valid;
    zero_attacker.attackers.front().manpower = 0;
    BattleCalculationInput empty_defenders = valid;
    empty_defenders.defenders.clear();
    BattleCalculationInput low_attacker_roll = valid;
    low_attacker_roll.attacker_random_tenths = 6;
    BattleCalculationInput high_defender_roll = valid;
    high_defender_roll.defender_random_tenths = 15;
    BattleCalculationInput invalid_terrain = valid;
    invalid_terrain.terrain_defense_bonus = -1;
    if (!expect(
            expect_invalid(zero_attacker) && expect_invalid(empty_defenders) &&
                expect_invalid(low_attacker_roll) &&
                expect_invalid(high_defender_roll) && expect_invalid(invalid_terrain),
            "invalid required inputs were not rejected"
        )) {
        return false;
    }

    BattleCalculationInput duplicate_ids = valid;
    duplicate_ids.defenders.push_back(
        {ArmyId{"defender"}, CountryId{"verdantia"}, 1, 0}
    );
    BattleCalculationInput zero_defender = valid;
    zero_defender.defenders.front().manpower = 0;
    BattleCalculationInput high_attacker_level = valid;
    high_attacker_level.attacker_military_level = 9;
    BattleCalculationInput low_defender_level = valid;
    low_defender_level.defenders.front().military_level = -1;
    if (!expect(
            expect_invalid(duplicate_ids) && expect_invalid(zero_defender) &&
                expect_invalid(high_attacker_level) && expect_invalid(low_defender_level),
            "army IDs, manpower, or military levels were not validated"
        )) {
        return false;
    }

    for (const std::int32_t bonus : std::array{0, 10, 20, 30, 50}) {
        BattleCalculationInput terrain_input = valid;
        terrain_input.terrain_defense_bonus = bonus;
        const BattleCalculation terrain = BattleCalculator::calculate(terrain_input);
        const std::int64_t expected_final =
            terrain.defender_base_strength * (100 + bonus) / 100;
        if (!expect(
                terrain.defender_final_strength == expected_final,
                "terrain defense bonus produced the wrong final strength"
            )) {
            return false;
        }
    }

    const BattleCalculation large = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1'000'000'000'000}}, 8,
        {{
            ArmyId{"defender"},
            CountryId{"solmere"},
            1'000'000'000'000,
            8,
        }},
        30, 14, 14,
    });
    if (!expect(
            large.attacker_base_strength > 0 &&
                large.defender_base_strength > 0 &&
                large.defender_final_strength > 0 &&
                large.attacker_remaining_manpower >= 0 &&
                large.defender_remaining_manpower >= 0,
            "large battle overflowed or produced negative manpower"
        )) {
        return false;
    }

    const BattleCalculation weighted_boundary = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, 1}}, 0,
        {
            {ArmyId{"level_3"}, CountryId{"solmere"}, 1, 3},
            {
                ArmyId{"level_4"},
                CountryId{"verdantia"},
                1'000'000'000'000'000'000,
                4,
            },
        },
        0, 10, 10,
    });
    if (!expect(
            weighted_boundary.defender_military_level == 3,
            "large weighted level just below four rounded up"
        )) {
        return false;
    }

    constexpr std::int64_t maximum = std::numeric_limits<std::int64_t>::max();
    const BattleCalculation exact_limit = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, maximum}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, maximum, 0}},
        0, 10, 10,
    });
    if (!expect(
            exact_limit.attacker_base_strength == maximum &&
                exact_limit.defender_base_strength == maximum &&
                exact_limit.defender_final_strength == maximum,
            "an exact INT64_MAX strength crossed the exclusive upper bound"
        )) {
        return false;
    }

    constexpr std::int64_t root_quarter = maximum / 4;
    constexpr std::int64_t almost_four_quarters = root_quarter * 4 - 1;
    const BattleCalculation near_integer_strength = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, almost_four_quarters}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, root_quarter, 0}},
        0, 10, 10,
    });
    if (!expect(
            near_integer_strength.attacker_base_strength == root_quarter * 2 - 1,
            "large square-root strength just below an integer rounded up"
        )) {
        return false;
    }

    constexpr std::int64_t terrain_base = (maximum / 13) * 10;
    constexpr std::int64_t terrain_expected = (maximum / 13) * 13;
    const BattleCalculation near_limit_terrain = BattleCalculator::calculate({
        {{ArmyId{"attacker"}, terrain_base}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, terrain_base, 0}},
        30, 10, 10,
    });
    if (!expect(
            near_limit_terrain.defender_base_strength == terrain_base &&
                near_limit_terrain.defender_final_strength == terrain_expected,
            "near-limit terrain scaling was not exact"
        )) {
        return false;
    }

    BattleCalculationInput overflowing_strength{
        {{ArmyId{"attacker"}, maximum}}, 1,
        {{ArmyId{"defender"}, CountryId{"solmere"}, maximum, 0}},
        0, 10, 10,
    };
    BattleCalculationInput overflowing_terrain{
        {{ArmyId{"attacker"}, maximum}}, 0,
        {{ArmyId{"defender"}, CountryId{"solmere"}, maximum, 0}},
        10, 10, 10,
    };
    if (!expect(
            expect_overflow(overflowing_strength) &&
                expect_overflow(overflowing_terrain),
            "strength at or above 2^63 was not rejected"
        )) {
        return false;
    }

    return true;
}
