#include "province/core/command_processor.hpp"
#include "province/core/country.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/economy_system.hpp"
#include "province/core/population_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/road.hpp"
#include "province/core/game_clock.hpp"
#include "province/core/game_state.hpp"
#include "province/core/province.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/stable_id.hpp"
#include "province/core/version.hpp"

#include <iostream>
#include <array>
#include <stdexcept>

int main() {
    using province::core::Country;
    using province::core::CountryId;
    using province::core::ArmyId;
    using province::core::GameClock;
    using province::core::GameState;
    using province::core::Province;
    using province::core::ProvinceId;
    using province::core::ScenarioLoader;
    using province::core::AdvanceTurnCommand;
    using province::core::CommandProcessor;
    using province::core::CommandResult;
    using province::core::TurnAdvancedEvent;
    using province::core::EconomyResolvedEvent;
    using province::core::PopulationResolvedEvent;
    using province::core::MovementPointsGrantedEvent;
    using province::core::BuildRoadCommand;
    using province::core::RecruitArmyCommand;
    using province::core::MoveArmyCommand;
    using province::core::ArmyRecruitedEvent;
    using province::core::RoadBuiltEvent;
    using province::core::RoadLevel;

    GameClock clock{1000, 11};
    clock.advance_months(3);

    if (clock.year() != 1001 || clock.month() != 2) {
        std::cerr << "GameClock rollover failed\n";
        return 1;
    }

    bool rejected_invalid_duration = false;
    try {
        clock.advance_months(0);
    } catch (const std::invalid_argument&) {
        rejected_invalid_duration = true;
    }

    if (!rejected_invalid_duration) {
        std::cerr << "GameClock accepted invalid duration\n";
        return 1;
    }

    bool rejected_invalid_id = false;
    try {
        [[maybe_unused]] const CountryId invalid_id{"Not Stable"};
    } catch (const std::invalid_argument&) {
        rejected_invalid_id = true;
    }
    if (!rejected_invalid_id) {
        std::cerr << "StableId accepted invalid characters\n";
        return 1;
    }

    GameState state{GameClock{1000, 1}};
    state.add_country(Country{CountryId{"auroria"}, "Auroria", 0xC94B4B, 10'000});
    state.add_country(Country{CountryId{"verdantia"}, "Verdantia", 0x4FA66B, 8'000});

    state.add_province(Province{
        ProvinceId{"northplain"},
        "North Plain",
        CountryId{"auroria"},
        120'000,
        2'000,
        80,
        {ProvinceId{"southpass"}},
    });
    state.add_province(Province{
        ProvinceId{"southpass"},
        "South Pass",
        CountryId{"verdantia"},
        90'000,
        1'500,
        60,
        {ProvinceId{"northplain"}},
    });

    if (state.country_count() != 2 || state.province_count() != 2) {
        std::cerr << "GameState entity counts are incorrect\n";
        return 1;
    }
    if (!state.validate().empty()) {
        std::cerr << "Valid GameState failed validation\n";
        return 1;
    }

    bool rejected_duplicate_country = false;
    try {
        state.add_country(Country{CountryId{"auroria"}, "Duplicate", 0, 0});
    } catch (const std::invalid_argument&) {
        rejected_duplicate_country = true;
    }
    if (!rejected_duplicate_country) {
        std::cerr << "GameState accepted a duplicate country ID\n";
        return 1;
    }

    const GameState loaded_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    if (loaded_state.country_count() != 4 || loaded_state.province_count() != 8) {
        std::cerr << "ScenarioLoader returned incorrect entity counts\n";
        return 1;
    }
    if (loaded_state.find_country(CountryId{"auroria"}) == nullptr ||
        loaded_state.find_province(ProvinceId{"northreach"}) == nullptr) {
        std::cerr << "ScenarioLoader did not create expected entities\n";
        return 1;
    }

    bool reported_missing_files = false;
    try {
        [[maybe_unused]] const GameState missing =
            ScenarioLoader::load("game/data/does-not-exist", GameClock{1000, 1});
    } catch (const province::core::DataLoadError&) {
        reported_missing_files = true;
    }
    if (!reported_missing_files) {
        std::cerr << "ScenarioLoader did not report missing data files\n";
        return 1;
    }

    GameState recruitment_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor recruitment_processor;
    const CommandResult recruited = recruitment_processor.execute(
        recruitment_state,
        RecruitArmyCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            1'000,
        }
    );
    const Country* recruiting_country =
        recruitment_state.find_country(CountryId{"auroria"});
    const Province* recruiting_province =
        recruitment_state.find_province(ProvinceId{"northreach"});
    if (!recruited.accepted || recruited.events.size() != 1 ||
        recruitment_state.army_count() != 1 || recruiting_country == nullptr ||
        recruiting_country->treasury != 9'000 || recruiting_province == nullptr ||
        recruiting_province->soldier_population != 1'000) {
        std::cerr << "RecruitArmyCommand did not transfer funds and soldiers correctly\n";
        return 1;
    }
    const auto& recruited_event =
        std::get<ArmyRecruitedEvent>(recruited.events.front().payload);
    const province::core::Army* recruited_army =
        recruitment_state.find_army(recruited_event.army_id);
    if (recruited_army == nullptr || recruited_event.cost != 1'000 ||
        recruited_army->manpower != 1'000 ||
        recruited_army->province_id != ProvinceId{"northreach"}) {
        std::cerr << "ArmyRecruitedEvent or army entity is incorrect\n";
        return 1;
    }

    const CommandResult insufficient_soldiers = recruitment_processor.execute(
        recruitment_state,
        RecruitArmyCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            2'000,
        }
    );
    const CommandResult foreign_recruitment = recruitment_processor.execute(
        recruitment_state,
        RecruitArmyCommand{
            CountryId{"auroria"},
            ProvinceId{"greenvale"},
            500,
        }
    );
    const CommandResult invalid_recruitment = recruitment_processor.execute(
        recruitment_state,
        RecruitArmyCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            0,
        }
    );
    if (insufficient_soldiers.accepted || foreign_recruitment.accepted ||
        invalid_recruitment.accepted || recruitment_state.army_count() != 1 ||
        recruitment_state.find_country(CountryId{"auroria"})->treasury != 9'000) {
        std::cerr << "Rejected recruitment command changed game state\n";
        return 1;
    }

    GameState normal_move_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor normal_move_processor;
    const CommandResult normal_recruit = normal_move_processor.execute(
        normal_move_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 1'000}
    );
    const ArmyId normal_army_id =
        std::get<ArmyRecruitedEvent>(normal_recruit.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult normal_month = normal_move_processor.execute(
        normal_move_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult normal_move = normal_move_processor.execute(
        normal_move_state,
        MoveArmyCommand{normal_army_id, ProvinceId{"westmark"}}
    );
    const CommandResult normal_move_back = normal_move_processor.execute(
        normal_move_state,
        MoveArmyCommand{normal_army_id, ProvinceId{"northreach"}}
    );
    if (!normal_move.accepted || normal_move_back.accepted ||
        normal_move_state.find_army(normal_army_id)->movement_points != 0 ||
        normal_move_state.find_army(normal_army_id)->province_id != ProvinceId{"westmark"}) {
        std::cerr << "Normal connection movement cost is incorrect\n";
        return 1;
    }

    GameState paved_move_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor paved_move_processor;
    const CommandResult paved_recruit = paved_move_processor.execute(
        paved_move_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 1'000}
    );
    const ArmyId paved_army_id =
        std::get<ArmyRecruitedEvent>(paved_recruit.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult paved_road = paved_move_processor.execute(
        paved_move_state,
        BuildRoadCommand{
            CountryId{"auroria"}, ProvinceId{"northreach"}, ProvinceId{"westmark"}
        }
    );
    [[maybe_unused]] const CommandResult paved_month = paved_move_processor.execute(
        paved_move_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult paved_outbound = paved_move_processor.execute(
        paved_move_state,
        MoveArmyCommand{paved_army_id, ProvinceId{"westmark"}}
    );
    const CommandResult paved_return = paved_move_processor.execute(
        paved_move_state,
        MoveArmyCommand{paved_army_id, ProvinceId{"northreach"}}
    );
    if (!paved_outbound.accepted || !paved_return.accepted ||
        paved_move_state.find_army(paved_army_id)->movement_points != 0 ||
        paved_move_state.find_army(paved_army_id)->province_id != ProvinceId{"northreach"}) {
        std::cerr << "Paved road did not allow two moves per monthly allowance\n";
        return 1;
    }
    const CommandResult foreign_move = paved_move_processor.execute(
        paved_move_state,
        MoveArmyCommand{paved_army_id, ProvinceId{"redpass"}}
    );
    if (foreign_move.accepted) {
        std::cerr << "Army entered foreign territory during peace\n";
        return 1;
    }

    GameState road_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor road_processor;
    const CommandResult road_built = road_processor.execute(
        road_state,
        BuildRoadCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            ProvinceId{"westmark"},
        }
    );
    const Country* road_country = road_state.find_country(CountryId{"auroria"});
    if (!road_built.accepted || road_built.events.size() != 1 ||
        road_country == nullptr || road_country->treasury != 9'500 ||
        road_state.road_level(ProvinceId{"northreach"}, ProvinceId{"westmark"}) !=
            RoadLevel::paved) {
        std::cerr << "BuildRoadCommand did not build and charge for a paved road\n";
        return 1;
    }
    const auto& road_event = std::get<RoadBuiltEvent>(road_built.events.front().payload);
    if (road_event.cost != 500 || road_built.events.front().sequence != 1) {
        std::cerr << "RoadBuiltEvent contained incorrect data\n";
        return 1;
    }

    const CommandResult duplicate_road = road_processor.execute(
        road_state,
        BuildRoadCommand{
            CountryId{"auroria"},
            ProvinceId{"westmark"},
            ProvinceId{"northreach"},
        }
    );
    const CommandResult foreign_road = road_processor.execute(
        road_state,
        BuildRoadCommand{
            CountryId{"auroria"},
            ProvinceId{"westmark"},
            ProvinceId{"greenvale"},
        }
    );
    const CommandResult non_adjacent_road = road_processor.execute(
        road_state,
        BuildRoadCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            ProvinceId{"greenvale"},
        }
    );
    if (duplicate_road.accepted || foreign_road.accepted || non_adjacent_road.accepted ||
        road_state.find_country(CountryId{"auroria"})->treasury != 9'500) {
        std::cerr << "Road validation failed or charged for a rejected command\n";
        return 1;
    }

    GameState poor_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    Country* poor_country = poor_state.find_country(CountryId{"auroria"});
    if (poor_country == nullptr) {
        std::cerr << "Road test could not find paying country\n";
        return 1;
    }
    poor_country->treasury = 499;
    CommandProcessor poor_processor;
    const CommandResult unaffordable_road = poor_processor.execute(
        poor_state,
        BuildRoadCommand{
            CountryId{"auroria"},
            ProvinceId{"northreach"},
            ProvinceId{"westmark"},
        }
    );
    if (unaffordable_road.accepted || poor_country->treasury != 499 ||
        poor_state.road_level(ProvinceId{"northreach"}, ProvinceId{"westmark"}) !=
            RoadLevel::none) {
        std::cerr << "Unaffordable road command changed game state\n";
        return 1;
    }

    GameState turn_state = ScenarioLoader::load("game/data", GameClock{1000, 11});
    CommandProcessor processor;
    const CommandResult accepted = processor.execute(turn_state, AdvanceTurnCommand{3});
    if (!accepted.accepted || turn_state.clock().year() != 1001 ||
        turn_state.clock().month() != 2 || accepted.events.size() != 4) {
        std::cerr << "AdvanceTurnCommand did not advance the state correctly\n";
        return 1;
    }
    const auto& economy_event = std::get<EconomyResolvedEvent>(accepted.events[0].payload);
    const auto& population_event =
        std::get<PopulationResolvedEvent>(accepted.events[1].payload);
    const auto& movement_event =
        std::get<MovementPointsGrantedEvent>(accepted.events[2].payload);
    const auto& turn_event = std::get<TurnAdvancedEvent>(accepted.events[3].payload);
    if (accepted.events[0].sequence != 1 || accepted.events[1].sequence != 2 ||
        accepted.events[2].sequence != 3 || accepted.events[3].sequence != 4 ||
        economy_event.elapsed_months != 3 || turn_event.elapsed_months != 3 ||
        movement_event.elapsed_months != 3 ||
        turn_event.previous_year != 1000 || turn_event.previous_month != 11) {
        std::cerr << "TurnAdvancedEvent contained incorrect data\n";
        return 1;
    }
    const Country* auroria_after_turn = turn_state.find_country(CountryId{"auroria"});
    if (auroria_after_turn == nullptr || auroria_after_turn->treasury != 10'450) {
        std::cerr << "EconomySystem did not add proportional monthly income\n";
        return 1;
    }
    bool found_auroria_income = false;
    for (const auto& income : economy_event.incomes) {
        if (income.country_id == CountryId{"auroria"}) {
            found_auroria_income = income.amount == 450;
        }
    }
    if (!found_auroria_income) {
        std::cerr << "EconomyResolvedEvent did not report Auroria income\n";
        return 1;
    }
    const Province* northreach_after_turn =
        turn_state.find_province(ProvinceId{"northreach"});
    if (northreach_after_turn == nullptr ||
        northreach_after_turn->population != 120'360 ||
        northreach_after_turn->soldier_population != 2'000 ||
        population_event.elapsed_months != 3) {
        std::cerr << "PopulationSystem produced an incorrect three-month result\n";
        return 1;
    }

    for (const std::int32_t months : std::array{1, 3, 6, 12}) {
        GameState proportional_state =
            ScenarioLoader::load("game/data", GameClock{1000, 1});
        CommandProcessor proportional_processor;
        const CommandResult proportional_result = proportional_processor.execute(
            proportional_state,
            AdvanceTurnCommand{months}
        );
        const Country* proportional_country =
            proportional_state.find_country(CountryId{"auroria"});
        if (!proportional_result.accepted || proportional_country == nullptr ||
            proportional_country->treasury != 10'000 + 150 * months) {
            std::cerr << "Economy income is not proportional for turn length "
                      << months << "\n";
            return 1;
        }
    }

    GameState single_turn_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    GameState monthly_turn_state = single_turn_state;
    CommandProcessor single_turn_processor;
    CommandProcessor monthly_turn_processor;
    [[maybe_unused]] const CommandResult annual_result = single_turn_processor.execute(
        single_turn_state,
        AdvanceTurnCommand{12}
    );
    for (std::int32_t month = 0; month < 12; ++month) {
        [[maybe_unused]] const CommandResult monthly_result = monthly_turn_processor.execute(
            monthly_turn_state,
            AdvanceTurnCommand{1}
        );
    }
    const Province* annual_province =
        single_turn_state.find_province(ProvinceId{"northreach"});
    const Province* monthly_province =
        monthly_turn_state.find_province(ProvinceId{"northreach"});
    if (annual_province == nullptr || monthly_province == nullptr ||
        annual_province->population != monthly_province->population ||
        annual_province->population_growth_remainder !=
            monthly_province->population_growth_remainder) {
        std::cerr << "Population growth differs between 12-month and monthly turns\n";
        return 1;
    }

    const CommandResult rejected = processor.execute(turn_state, AdvanceTurnCommand{2});
    if (rejected.accepted || rejected.error.empty() ||
        turn_state.clock().year() != 1001 || turn_state.clock().month() != 2) {
        std::cerr << "CommandProcessor accepted an unsupported turn length\n";
        return 1;
    }

    std::cout << "Project Province core " << province::core::version()
              << " smoke test passed\n";
    return 0;
}
#include "province/core/army.hpp"
#include "province/core/army_system.hpp"
