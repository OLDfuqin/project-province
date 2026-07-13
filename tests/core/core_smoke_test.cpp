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
#include "province/core/game_status.hpp"
#include "province/core/province.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/save_game.hpp"
#include "province/core/stable_id.hpp"
#include "province/core/version.hpp"

#include <iostream>
#include <array>
#include <filesystem>
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
    using province::core::DeclareWarCommand;
    using province::core::MakePeaceCommand;
    using province::core::PeaceSettlementPolicy;
    using province::core::ResearchTechnologyCommand;
    using province::core::TechnologyTrack;
    using province::core::ArmyRecruitedEvent;
    using province::core::ArmyMovedEvent;
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
    if (loaded_state.country_count() != 4 || loaded_state.province_count() != 32) {
        std::cerr << "ScenarioLoader returned incorrect entity counts\n";
        return 1;
    }
    if (loaded_state.find_country(CountryId{"auroria"}) == nullptr ||
        loaded_state.find_province(ProvinceId{"northreach"}) == nullptr) {
        std::cerr << "ScenarioLoader did not create expected entities\n";
        return 1;
    }
    const province::core::GameStatus initial_status =
        province::core::GameStatusSystem{}.evaluate(loaded_state, CountryId{"auroria"});
    if (initial_status.game_over ||
        initial_status.countries.at(CountryId{"auroria"}).controlled_provinces != 8) {
        std::cerr << "Initial game status is incorrect\n";
        return 1;
    }
    GameState elimination_state = loaded_state;
    for (const auto& [province_id, province] : loaded_state.provinces()) {
        if (province.owner_id == CountryId{"solmere"}) {
            elimination_state.transfer_province_ownership(province_id, CountryId{"auroria"});
        }
    }
    const province::core::GameStatus elimination_status =
        province::core::GameStatusSystem{}.evaluate(elimination_state, CountryId{"auroria"});
    if (!elimination_status.countries.at(CountryId{"solmere"}).eliminated ||
        elimination_status.game_over) {
        std::cerr << "Country elimination status is incorrect\n";
        return 1;
    }
    GameState conquest_state = loaded_state;
    for (const auto& [province_id, province] : loaded_state.provinces()) {
        static_cast<void>(province);
        conquest_state.transfer_province_ownership(province_id, CountryId{"auroria"});
    }
    const province::core::GameStatus conquest_status =
        province::core::GameStatusSystem{}.evaluate(conquest_state, CountryId{"auroria"});
    if (!conquest_status.game_over || !conquest_status.player_won ||
        conquest_status.winner_id != CountryId{"auroria"}) {
        std::cerr << "Conquest victory status is incorrect\n";
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
        recruiting_province->recruitable_population != 1'000) {
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
    GameState terrain_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor terrain_processor;
    const CommandResult terrain_recruit = terrain_processor.execute(
        terrain_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 100}
    );
    const ArmyId terrain_army =
        std::get<ArmyRecruitedEvent>(terrain_recruit.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult terrain_months = terrain_processor.execute(
        terrain_state, AdvanceTurnCommand{3}
    );
    [[maybe_unused]] const CommandResult plains_move = terrain_processor.execute(
        terrain_state, MoveArmyCommand{terrain_army, ProvinceId{"z_nr_1"}}
    );
    const CommandResult mountain_move = terrain_processor.execute(
        terrain_state, MoveArmyCommand{terrain_army, ProvinceId{"z_nr_2"}}
    );
    if (!mountain_move.accepted ||
        std::get<ArmyMovedEvent>(mountain_move.events.front().payload).movement_cost != 4 ||
        terrain_state.find_army(terrain_army)->movement_points != 0) {
        std::cerr << "Mountain terrain movement cost is incorrect\n";
        return 1;
    }
    const CommandResult war_declared = paved_move_processor.execute(
        paved_move_state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    const CommandResult duplicate_war = paved_move_processor.execute(
        paved_move_state,
        DeclareWarCommand{CountryId{"solmere"}, CountryId{"auroria"}}
    );
    [[maybe_unused]] const CommandResult war_month = paved_move_processor.execute(
        paved_move_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult wartime_move = paved_move_processor.execute(
        paved_move_state,
        MoveArmyCommand{paved_army_id, ProvinceId{"redpass"}}
    );
    if (!war_declared.accepted || duplicate_war.accepted || !wartime_move.accepted ||
        !paved_move_state.are_at_war(CountryId{"auroria"}, CountryId{"solmere"}) ||
        paved_move_state.find_army(paved_army_id)->province_id != ProvinceId{"redpass"} ||
        paved_move_state.controller_of(ProvinceId{"redpass"}) != CountryId{"auroria"}) {
        std::cerr << "War declaration did not enable hostile territory movement\n";
        return 1;
    }
    const CommandResult restored_peace = paved_move_processor.execute(
        paved_move_state,
        MakePeaceCommand{
            CountryId{"auroria"},
            CountryId{"solmere"},
            PeaceSettlementPolicy::restore_legal_owners,
        }
    );
    const CommandResult duplicate_peace = paved_move_processor.execute(
        paved_move_state,
        MakePeaceCommand{
            CountryId{"auroria"},
            CountryId{"solmere"},
            PeaceSettlementPolicy::restore_legal_owners,
        }
    );
    if (!restored_peace.accepted || duplicate_peace.accepted ||
        paved_move_state.are_at_war(CountryId{"auroria"}, CountryId{"solmere"}) ||
        paved_move_state.controller_of(ProvinceId{"redpass"}) != CountryId{"solmere"} ||
        paved_move_state.find_army(paved_army_id)->province_id != ProvinceId{"northreach"}) {
        std::cerr << "Status quo peace did not restore borders and repatriate armies\n";
        return 1;
    }

    GameState battle_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor battle_processor;
    const CommandResult attacker_recruit = battle_processor.execute(
        battle_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 1'000}
    );
    const CommandResult defender_recruit = battle_processor.execute(
        battle_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"redpass"}, 500}
    );
    const ArmyId attacker_id =
        std::get<ArmyRecruitedEvent>(attacker_recruit.events.front().payload).army_id;
    const ArmyId defender_id =
        std::get<ArmyRecruitedEvent>(defender_recruit.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult battle_war = battle_processor.execute(
        battle_state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    [[maybe_unused]] const CommandResult battle_month = battle_processor.execute(
        battle_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult battle_move = battle_processor.execute(
        battle_state,
        MoveArmyCommand{attacker_id, ProvinceId{"redpass"}}
    );
    if (!battle_move.accepted || battle_move.events.size() != 2 ||
        battle_state.find_army(attacker_id) == nullptr ||
        battle_state.find_army(attacker_id)->manpower != 875 ||
        battle_state.find_army(defender_id) == nullptr ||
        battle_state.find_army(defender_id)->manpower != 250 ||
        battle_state.find_army(defender_id)->province_id != ProvinceId{"goldcoast"} ||
        battle_state.controller_of(ProvinceId{"redpass"}) != CountryId{"auroria"} ||
        battle_state.find_province(ProvinceId{"redpass"})->owner_id != CountryId{"solmere"}) {
        std::cerr << "Battle casualties, retreat or occupation are incorrect\n";
        return 1;
    }
    const auto& battle =
        std::get<province::core::BattleResolution>(battle_move.events.back().payload);
    if (!battle.occurred || !battle.attacker_won || !battle.province_occupied ||
        battle.armies.size() != 2) {
        std::cerr << "BattleResolved event is incorrect\n";
        return 1;
    }
    const CommandResult occupied_recruitment = battle_processor.execute(
        battle_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"redpass"}, 100}
    );
    if (occupied_recruitment.accepted) {
        std::cerr << "Legal owner recruited soldiers in an occupied province\n";
        return 1;
    }
    const CommandResult annexation_peace = battle_processor.execute(
        battle_state,
        MakePeaceCommand{
            CountryId{"auroria"},
            CountryId{"solmere"},
            PeaceSettlementPolicy::annex_occupied_provinces,
        }
    );
    if (!annexation_peace.accepted ||
        battle_state.find_province(ProvinceId{"redpass"})->owner_id != CountryId{"auroria"} ||
        battle_state.controller_of(ProvinceId{"redpass"}) != CountryId{"auroria"} ||
        battle_state.are_at_war(CountryId{"auroria"}, CountryId{"solmere"})) {
        std::cerr << "Annexation peace did not transfer occupied territory\n";
        return 1;
    }

    GameState defeat_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor defeat_processor;
    const CommandResult weak_recruit = defeat_processor.execute(
        defeat_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 300}
    );
    const CommandResult strong_recruit = defeat_processor.execute(
        defeat_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"redpass"}, 500}
    );
    const ArmyId weak_id =
        std::get<ArmyRecruitedEvent>(weak_recruit.events.front().payload).army_id;
    const ArmyId strong_id =
        std::get<ArmyRecruitedEvent>(strong_recruit.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult defeat_war = defeat_processor.execute(
        defeat_state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    [[maybe_unused]] const CommandResult defeat_month = defeat_processor.execute(
        defeat_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult defeated_attack = defeat_processor.execute(
        defeat_state,
        MoveArmyCommand{weak_id, ProvinceId{"redpass"}}
    );
    if (!defeated_attack.accepted || defeat_state.find_army(weak_id) == nullptr ||
        defeat_state.find_army(weak_id)->province_id != ProvinceId{"northreach"} ||
        defeat_state.find_army(weak_id)->manpower != 175 ||
        defeat_state.find_army(strong_id) == nullptr ||
        defeat_state.find_army(strong_id)->manpower != 425 ||
        defeat_state.controller_of(ProvinceId{"redpass"}) != CountryId{"solmere"}) {
        std::cerr << "Defeated attacker did not take losses and retreat\n";
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
    if (auroria_after_turn == nullptr || auroria_after_turn->treasury != 10'900) {
        std::cerr << "EconomySystem did not add proportional monthly income\n";
        return 1;
    }
    bool found_auroria_income = false;
    for (const auto& income : economy_event.incomes) {
        if (income.country_id == CountryId{"auroria"}) {
            found_auroria_income = income.amount == 900;
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
        northreach_after_turn->recruitable_population != 3'802 ||
        population_event.elapsed_months != 3) {
        std::cerr << "PopulationSystem produced an incorrect three-month result\n";
        return 1;
    }
    bool found_northreach_population_change = false;
    for (const auto& change : population_event.changes) {
        if (change.province_id == ProvinceId{"northreach"}) {
            found_northreach_population_change =
                change.previous_recruitable_population == 2'000 &&
                change.current_recruitable_population == 3'802 &&
                change.recruitable_growth == 1'802;
        }
    }
    if (!found_northreach_population_change) {
        std::cerr << "PopulationResolvedEvent did not aggregate recruitable growth\n";
        return 1;
    }

    GameState cap_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    Province* cap_province = cap_state.find_province(ProvinceId{"northreach"});
    if (cap_province == nullptr) {
        std::cerr << "Recruitable population cap fixture was missing\n";
        return 1;
    }
    cap_province->recruitable_population = 12'011;
    CommandProcessor cap_processor;
    const CommandResult cap_result = cap_processor.execute(cap_state, AdvanceTurnCommand{1});
    const Province* capped_province = cap_state.find_province(ProvinceId{"northreach"});
    if (!cap_result.accepted || capped_province == nullptr ||
        capped_province->population != 120'120 ||
        capped_province->recruitable_population != 12'012) {
        std::cerr << "Recruitable population did not stop at the ten-percent cap\n";
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
            proportional_country->treasury != 10'000 + 300 * months) {
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
        annual_province->recruitable_population !=
            monthly_province->recruitable_population ||
        annual_province->population_growth_remainder !=
            monthly_province->population_growth_remainder) {
        std::cerr << "Population growth differs between 12-month and monthly turns\n";
        return 1;
    }

    GameState economy_tech_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor economy_tech_processor;
    const CommandResult economy_research = economy_tech_processor.execute(
        economy_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    [[maybe_unused]] const CommandResult economy_tech_month = economy_tech_processor.execute(
        economy_tech_state,
        AdvanceTurnCommand{1}
    );
    if (!economy_research.accepted || economy_tech_state.find_technology(
            CountryId{"auroria"})->economy_level != 1 ||
        economy_tech_state.find_country(CountryId{"auroria"})->treasury != 9'329) {
        std::cerr << "Economy technology did not increase monthly income by ten percent\n";
        return 1;
    }
    [[maybe_unused]] const CommandResult economy_level_two = economy_tech_processor.execute(
        economy_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    [[maybe_unused]] const CommandResult economy_level_three = economy_tech_processor.execute(
        economy_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    const CommandResult economy_over_maximum = economy_tech_processor.execute(
        economy_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::economy}
    );
    if (economy_over_maximum.accepted) {
        std::cerr << "Technology research exceeded the maximum level\n";
        return 1;
    }

    GameState roads_tech_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor roads_tech_processor;
    const CommandResult roads_research = roads_tech_processor.execute(
        roads_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::roads}
    );
    const CommandResult roads_army = roads_tech_processor.execute(
        roads_tech_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 500}
    );
    const ArmyId roads_army_id =
        std::get<ArmyRecruitedEvent>(roads_army.events.front().payload).army_id;
    const CommandResult discounted_road = roads_tech_processor.execute(
        roads_tech_state,
        BuildRoadCommand{
            CountryId{"auroria"}, ProvinceId{"northreach"}, ProvinceId{"westmark"}
        }
    );
    [[maybe_unused]] const CommandResult roads_tech_month = roads_tech_processor.execute(
        roads_tech_state,
        AdvanceTurnCommand{1}
    );
    if (!roads_research.accepted || !discounted_road.accepted ||
        std::get<RoadBuiltEvent>(discounted_road.events.front().payload).cost != 400 ||
        roads_tech_state.find_army(roads_army_id)->movement_points != 3) {
        std::cerr << "Road technology did not improve cost and movement allowance\n";
        return 1;
    }

    GameState military_tech_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor military_tech_processor;
    const CommandResult military_attacker = military_tech_processor.execute(
        military_tech_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 500}
    );
    [[maybe_unused]] const CommandResult military_defender = military_tech_processor.execute(
        military_tech_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"redpass"}, 525}
    );
    const ArmyId military_attacker_id =
        std::get<ArmyRecruitedEvent>(military_attacker.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult military_research = military_tech_processor.execute(
        military_tech_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::military}
    );
    [[maybe_unused]] const CommandResult military_war = military_tech_processor.execute(
        military_tech_state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    [[maybe_unused]] const CommandResult military_month = military_tech_processor.execute(
        military_tech_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult technology_battle = military_tech_processor.execute(
        military_tech_state,
        MoveArmyCommand{military_attacker_id, ProvinceId{"redpass"}}
    );
    const auto& technology_battle_result =
        std::get<province::core::BattleResolution>(technology_battle.events.back().payload);
    if (!technology_battle.accepted || !technology_battle_result.attacker_won ||
        !technology_battle_result.province_occupied) {
        std::cerr << "Military technology did not contribute to effective strength\n";
        return 1;
    }

    GameState ai_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor ai_processor;
    ai_processor.enable_ai(CountryId{"auroria"});
    const CommandResult first_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult second_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult third_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    const CommandResult fourth_ai_month = ai_processor.execute(
        ai_state,
        AdvanceTurnCommand{1}
    );
    std::int64_t player_armies = 0;
    for (const auto& [army_id, army] : ai_state.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id == CountryId{"auroria"}) {
            ++player_armies;
        }
    }
    if (!first_ai_month.accepted || !second_ai_month.accepted ||
        !third_ai_month.accepted || !fourth_ai_month.accepted ||
        ai_state.army_count() != 9 ||
        player_armies != 0 || ai_state.relations().empty() ||
        ai_state.occupations().empty() || first_ai_month.events.size() != 7) {
        std::cerr << "AI did not recruit, declare war and advance deterministically\n";
        return 1;
    }

    GameState ai_path_state = ScenarioLoader::load("game/data", GameClock{1000, 1});
    CommandProcessor ai_path_processor;
    const CommandResult rear_army_result = ai_path_processor.execute(
        ai_path_state,
        RecruitArmyCommand{CountryId{"solmere"}, ProvinceId{"goldcoast"}, 500}
    );
    const ArmyId rear_army_id =
        std::get<ArmyRecruitedEvent>(rear_army_result.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult ai_path_war = ai_path_processor.execute(
        ai_path_state,
        DeclareWarCommand{CountryId{"solmere"}, CountryId{"auroria"}}
    );
    ai_path_processor.enable_ai(CountryId{"auroria"});
    [[maybe_unused]] const CommandResult ai_path_month = ai_path_processor.execute(
        ai_path_state,
        AdvanceTurnCommand{1}
    );
    if (ai_path_state.find_army(rear_army_id)->province_id != ProvinceId{"redpass"}) {
        std::cerr << "AI pathfinding did not move a rear army toward the front\n";
        return 1;
    }

    const std::filesystem::path save_path = "build/save_game_roundtrip_test.json";
    GameState save_state = ScenarioLoader::load("game/data", GameClock{1200, 6});
    CommandProcessor save_processor;
    [[maybe_unused]] const CommandResult save_technology = save_processor.execute(
        save_state,
        ResearchTechnologyCommand{CountryId{"auroria"}, TechnologyTrack::roads}
    );
    const CommandResult save_recruitment = save_processor.execute(
        save_state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"northreach"}, 500}
    );
    const ArmyId saved_army_id =
        std::get<ArmyRecruitedEvent>(save_recruitment.events.front().payload).army_id;
    [[maybe_unused]] const CommandResult save_road = save_processor.execute(
        save_state,
        BuildRoadCommand{
            CountryId{"auroria"}, ProvinceId{"northreach"}, ProvinceId{"westmark"}
        }
    );
    [[maybe_unused]] const CommandResult save_war = save_processor.execute(
        save_state,
        DeclareWarCommand{CountryId{"auroria"}, CountryId{"solmere"}}
    );
    [[maybe_unused]] const CommandResult save_month = save_processor.execute(
        save_state,
        AdvanceTurnCommand{1}
    );
    [[maybe_unused]] const CommandResult save_occupation = save_processor.execute(
        save_state,
        MoveArmyCommand{saved_army_id, ProvinceId{"redpass"}}
    );
    save_processor.enable_ai(CountryId{"auroria"});
    province::core::SaveGameSerializer::save(
        save_path,
        save_state,
        save_processor.next_event_sequence(),
        save_processor.human_country_id()
    );
    province::core::LoadedGame loaded_game =
        province::core::SaveGameSerializer::load(save_path);
    if (loaded_game.state.clock().year() != save_state.clock().year() ||
        loaded_game.state.clock().month() != save_state.clock().month() ||
        loaded_game.state.army_count() != save_state.army_count() ||
        loaded_game.state.road_level(ProvinceId{"northreach"}, ProvinceId{"westmark"}) !=
            RoadLevel::paved ||
        !loaded_game.state.are_at_war(CountryId{"auroria"}, CountryId{"solmere"}) ||
        loaded_game.state.controller_of(ProvinceId{"redpass"}) != CountryId{"auroria"} ||
        loaded_game.state.find_technology(CountryId{"auroria"})->roads_level != 1 ||
        loaded_game.state.find_army(saved_army_id) == nullptr ||
        loaded_game.state.find_army(saved_army_id)->movement_points !=
            save_state.find_army(saved_army_id)->movement_points ||
        loaded_game.next_event_sequence != save_processor.next_event_sequence() ||
        !loaded_game.human_country_id.has_value() ||
        *loaded_game.human_country_id != CountryId{"auroria"}) {
        std::cerr << "Save game round trip did not preserve simulation state\n";
        return 1;
    }
    CommandProcessor restored_processor;
    restored_processor.set_next_event_sequence(loaded_game.next_event_sequence);
    restored_processor.enable_ai(*loaded_game.human_country_id);
    const CommandResult post_load_recruitment = restored_processor.execute(
        loaded_game.state,
        RecruitArmyCommand{CountryId{"auroria"}, ProvinceId{"westmark"}, 100}
    );
    const auto& post_load_event =
        std::get<ArmyRecruitedEvent>(post_load_recruitment.events.front().payload);
    if (!post_load_recruitment.accepted || post_load_event.army_id != ArmyId{"army_2"} ||
        post_load_recruitment.events.front().sequence != save_processor.next_event_sequence()) {
        std::cerr << "Save game did not preserve entity and event sequences\n";
        return 1;
    }
    std::filesystem::remove(save_path);

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
