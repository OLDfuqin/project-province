#include "province/core/game_order.hpp"
#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/game_event.hpp"
#include "province/core/game_state.hpp"
#include "province/core/monthly_order_system.hpp"
#include "province/core/order_system.hpp"
#include "province/core/road_system.hpp"
#include "smoke_test_groups.hpp"

#include <iostream>
#include <variant>

namespace {

using namespace province::core;

GameState order_state() {
    GameState state{GameClock{1000, 1}};
    state.add_country(Country{CountryId{"alpha"}, "Alpha", 0, 100'000, "ALP", false});
    state.add_country(Country{CountryId{"beta"}, "Beta", 0, 100'000, "BET", false});
    state.add_country(Country{CountryId{"gamma"}, "Gamma", 0, 100'000, "GAM", false});
    state.add_province(Province{
        ProvinceId{"alpha_a"}, "Alpha A", CountryId{"alpha"},
        10'000, 5'000, 10'000, {ProvinceId{"alpha_b"}}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        ProvinceId{"gamma_a"}, "Gamma A", CountryId{"gamma"},
        10'000, 5'000, 10'000, {ProvinceId{"beta_a"}}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        ProvinceId{"alpha_b"}, "Alpha B", CountryId{"alpha"},
        10'000, 5'000, 10'000,
        {ProvinceId{"alpha_a"}, ProvinceId{"beta_a"}}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        ProvinceId{"beta_a"}, "Beta A", CountryId{"beta"},
        10'000, 5'000, 10'000,
        {ProvinceId{"alpha_b"}, ProvinceId{"gamma_a"}}, 0, TerrainType::plains,
    });
    state.find_technology(CountryId{"alpha"})->roads_level = 1;
    state.set_diplomatic_status(CountryId{"alpha"}, CountryId{"beta"}, DiplomaticStatus::war);
    state.set_diplomatic_status(CountryId{"gamma"}, CountryId{"beta"}, DiplomaticStatus::war);
    return state;
}

bool test_attack_target_country_lock() {
    GameState state = order_state();
    OrderSystem system;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ProvinceId gamma_a{"gamma_a"};
    const ArmyId first_alpha = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    const ArmyId second_alpha = state.create_army(CountryId{"alpha"}, alpha_b, 1'000);
    const ArmyId gamma = state.create_army(CountryId{"gamma"}, gamma_a, 1'000);
    state.find_army(first_alpha)->movement_points = 12;
    state.find_army(second_alpha)->movement_points = 8;
    state.find_army(gamma)->movement_points = 8;

    if (!system.queue_army_action(
            state, first_alpha, {alpha_a, alpha_b, beta_a}, true
        ).accepted ||
        !system.queue_army_action(state, second_alpha, {alpha_b, beta_a}, true).accepted ||
        system.queue_army_action(state, gamma, {gamma_a, beta_a}, true).accepted) {
        std::cerr << "Attack target lock did not allow one country and reject another\n";
        return false;
    }
    const std::vector<std::string> issues = state.validate();
    if (!issues.empty()) {
        std::cerr << "Valid same-country attack orders failed state validation\n";
        for (const std::string& issue : issues) std::cerr << "  " << issue << "\n";
        return false;
    }
    return true;
}

bool test_reachable_order_paths_and_costs() {
    GameState state = order_state();
    MovementSystem movement;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;

    state.set_occupation(beta_a, CountryId{"alpha"});
    const std::vector<ProvinceId> friendly_path =
        movement.find_order_path(state, army_id, beta_a);
    if (friendly_path != std::vector<ProvinceId>{alpha_a, alpha_b, beta_a} ||
        movement.path_cost_half(state, friendly_path) != 8) {
        std::cerr << "Range movement did not find the full two-edge friendly path\n";
        return false;
    }

    state.clear_occupation(beta_a);
    const std::vector<ProvinceId> attack_path =
        movement.find_order_path(state, army_id, beta_a);
    if (attack_path != std::vector<ProvinceId>{alpha_a, alpha_b, beta_a} ||
        movement.path_cost_half(state, attack_path) != 8) {
        std::cerr << "Range movement did not allow an enemy province as the final step\n";
        return false;
    }

    state.find_army(army_id)->movement_points = 11;
    if (!movement.find_order_path(state, army_id, beta_a).empty()) {
        std::cerr << "Range movement ignored the attack surcharge when checking reach\n";
        return false;
    }
    return true;
}

bool test_order_path_uses_weighted_dijkstra() {
    GameState state{GameClock{1000, 1}};
    const CountryId alpha{"alpha"};
    const ProvinceId start{"start"};
    const ProvinceId paved_mid{"paved_mid"};
    const ProvinceId target{"target"};
    state.add_country(Country{alpha, "Alpha", 0, 0, "ALP", false});
    state.add_province(Province{
        start, "Start", alpha, 1'000, 100, 100,
        {target, paved_mid}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        paved_mid, "Paved Mid", alpha, 1'000, 100, 100,
        {start, target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        target, "Target", alpha, 1'000, 100, 100,
        {start, paved_mid}, 0, TerrainType::mountains,
    });
    state.set_road_level(start, paved_mid, RoadLevel::paved);
    state.set_road_level(paved_mid, target, RoadLevel::paved);
    const ArmyId army_id = state.create_army(alpha, start, 1'000);
    state.find_army(army_id)->movement_points = 12;

    const MovementSystem movement;
    const std::vector<ProvinceId> path = movement.find_order_path(
        state,
        army_id,
        target
    );
    if (path != std::vector<ProvinceId>{start, paved_mid, target} ||
        movement.path_cost_half(state, path) != 4) {
        std::cerr << "Order path did not choose the cheaper weighted paved route\n";
        return false;
    }
    return true;
}

bool test_order_path_tie_breaks_by_stable_province_id() {
    GameState state{GameClock{1000, 1}};
    const CountryId alpha{"alpha"};
    const ProvinceId start{"start"};
    const ProvinceId alpha_mid{"alpha_mid"};
    const ProvinceId zulu_mid{"zulu_mid"};
    const ProvinceId target{"target"};
    state.add_country(Country{alpha, "Alpha", 0, 0, "ALP", false});
    state.add_province(Province{
        start, "Start", alpha, 1'000, 100, 100,
        {zulu_mid, alpha_mid}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        alpha_mid, "Alpha Mid", alpha, 1'000, 100, 100,
        {start, target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        zulu_mid, "Zulu Mid", alpha, 1'000, 100, 100,
        {start, target}, 0, TerrainType::plains,
    });
    state.add_province(Province{
        target, "Target", alpha, 1'000, 100, 100,
        {zulu_mid, alpha_mid}, 0, TerrainType::plains,
    });
    const ArmyId army_id = state.create_army(alpha, start, 1'000);
    state.find_army(army_id)->movement_points = 12;

    const std::vector<ProvinceId> path = MovementSystem{}.find_order_path(
        state,
        army_id,
        target
    );
    if (path != std::vector<ProvinceId>{start, alpha_mid, target}) {
        std::cerr << "Equal-cost order paths did not use stable province-ID ordering\n";
        return false;
    }
    return true;
}

bool test_queue_and_cancel_orders() {
    GameState state = order_state();
    OrderSystem system;
    const CountryId alpha{"alpha"};
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};

    const ArmyId army_id = state.create_army(alpha, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;

    const OrderOperationResult action = system.queue_army_action(
        state, army_id, {alpha_a, alpha_b, beta_a}, true
    );
    if (!action.accepted || !action.order_id.has_value() ||
        action.order_id->value() != "order_1" || state.orders().size() != 1 ||
        state.find_army(army_id)->movement_points != 0) {
        std::cerr << "Army action order did not reserve route and attack movement\n";
        return false;
    }
    const auto* action_order = std::get_if<ArmyActionOrder>(&state.orders().at(*action.order_id));
    if (action_order == nullptr || action_order->country_id != alpha ||
        action_order->origin != alpha_a || action_order->destination != beta_a ||
        action_order->path != std::vector<ProvinceId>{alpha_a, alpha_b, beta_a} ||
        action_order->reserved_movement_half != 12 || !action_order->is_attack) {
        std::cerr << "Army action order did not retain its typed execution data\n";
        return false;
    }
    if (system.queue_army_action(state, army_id, {alpha_a, alpha_b}, false).accepted) {
        std::cerr << "A second action order for one army was accepted\n";
        return false;
    }
    if (!system.cancel(state, *action.order_id).accepted ||
        state.find_army(army_id)->movement_points != 12 || !state.orders().empty()) {
        std::cerr << "Army action cancellation did not refund movement\n";
        return false;
    }

    const Province* population_before = state.find_province(alpha_a);
    const auto original_population = population_before->population;
    const auto original_recruitable = population_before->recruitable_population;
    const auto original_economy = population_before->base_economy;
    const auto original_treasury = state.find_country(alpha)->treasury;
    const OrderOperationResult recruitment =
        system.queue_recruitment(state, alpha, alpha_a, 2'000);
    if (!recruitment.accepted || recruitment.order_id->value() != "order_2" ||
        state.find_country(alpha)->treasury != original_treasury - 8'000 ||
        state.find_province(alpha_a)->population != original_population ||
        state.find_province(alpha_a)->recruitable_population != original_recruitable ||
        state.find_province(alpha_a)->base_economy != original_economy) {
        std::cerr << "Recruitment order did not prepay money and reserve population only\n";
        return false;
    }
    if (system.queue_recruitment(state, alpha, alpha_a, 3'001).accepted) {
        std::cerr << "Recruitment ignored population reserved by an existing order\n";
        return false;
    }
    const auto* recruitment_order =
        std::get_if<RecruitmentOrder>(&state.orders().at(*recruitment.order_id));
    if (recruitment_order == nullptr || recruitment_order->paid_cost != 8'000 ||
        recruitment_order->remaining_months != 1) {
        std::cerr << "Recruitment order lost cost or duration\n";
        return false;
    }
    if (!system.cancel(state, *recruitment.order_id).accepted ||
        state.find_country(alpha)->treasury != original_treasury) {
        std::cerr << "Recruitment cancellation did not refund its prepaid cost\n";
        return false;
    }

    const OrderOperationResult road =
        system.queue_road_construction(state, alpha, alpha_a, alpha_b);
    if (!road.accepted || road.order_id->value() != "order_3") {
        std::cerr << "Road construction order was rejected\n";
        return false;
    }
    const auto* road_order =
        std::get_if<RoadConstructionOrder>(&state.orders().at(*road.order_id));
    if (road_order == nullptr || road_order->paid_cost != 540 ||
        road_order->remaining_months != 1 ||
        state.road_level(alpha_a, alpha_b) != RoadLevel::none) {
        std::cerr << "Road order executed early or lost reservation data\n";
        return false;
    }
    if (system.queue_road_construction(state, alpha, alpha_b, alpha_a).accepted) {
        std::cerr << "Duplicate reverse-direction road order was accepted\n";
        return false;
    }
    const auto treasury_after_road = state.find_country(alpha)->treasury;

    const OrderOperationResult research =
        system.queue_research(state, alpha, TechnologyTrack::economy);
    if (!research.accepted || research.order_id->value() != "order_4" ||
        state.find_technology(alpha)->economy_level != 0) {
        std::cerr << "Research order was rejected or executed early\n";
        return false;
    }
    const auto* research_order =
        std::get_if<ResearchOrder>(&state.orders().at(*research.order_id));
    if (research_order == nullptr || research_order->previous_level != 0 ||
        research_order->target_level != 1 || research_order->paid_cost != 5'000 ||
        research_order->remaining_months != 2) {
        std::cerr << "Research order lost level, cost or duration data\n";
        return false;
    }
    if (system.queue_research(state, alpha, TechnologyTrack::military).accepted) {
        std::cerr << "A second research order for one country was accepted\n";
        return false;
    }
    if (!system.cancel(state, *research.order_id).accepted ||
        state.find_country(alpha)->treasury != treasury_after_road) {
        std::cerr << "Unprogressed research cancellation did not refund its cost\n";
        return false;
    }
    if (!system.cancel(state, *road.order_id).accepted ||
        state.find_country(alpha)->treasury != original_treasury) {
        std::cerr << "Road cancellation did not refund its cost\n";
        return false;
    }
    return true;
}

bool test_rejects_debt_and_preserves_state_on_failure() {
    GameState state = order_state();
    OrderSystem system;
    const CountryId alpha{"alpha"};
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    state.find_country(alpha)->treasury = -1;

    if (system.queue_recruitment(state, alpha, alpha_a, 1).accepted ||
        system.queue_road_construction(state, alpha, alpha_a, alpha_b).accepted ||
        system.queue_research(state, alpha, TechnologyTrack::economy).accepted ||
        !state.orders().empty() || state.find_country(alpha)->treasury != -1) {
        std::cerr << "A paid project was queued while the country was in debt\n";
        return false;
    }
    if (system.cancel(state, OrderId{"order_999"}).accepted || !state.validate().empty()) {
        std::cerr << "Missing cancellation mutated or invalidated order state\n";
        return false;
    }
    return true;
}

bool test_command_processor_queues_and_cancels_projects() {
    GameState state = order_state();
    CommandProcessor processor;
    const CountryId alpha{"alpha"};
    const ProvinceId alpha_a{"alpha_a"};
    const std::size_t army_count = state.army_count();
    const std::int64_t population = state.find_province(alpha_a)->population;

    const CommandResult queued = processor.execute(
        state, RecruitArmyCommand{alpha, alpha_a, 100}
    );
    if (!queued.accepted || queued.events.size() != 1 ||
        queued.events.front().type != GameEventType::order_created ||
        state.army_count() != army_count ||
        state.find_province(alpha_a)->population != population) {
        std::cerr << "Recruit command did not create a delayed order\n";
        return false;
    }
    const OrderId id = std::get<OrderCreatedEvent>(queued.events.front().payload).order_id;
    if (!state.orders().contains(id)) {
        std::cerr << "Order-created event did not reference persistent state\n";
        return false;
    }

    const CommandResult cancelled = processor.execute(state, CancelOrderCommand{id});
    if (!cancelled.accepted || cancelled.events.size() != 1 ||
        cancelled.events.front().type != GameEventType::order_cancelled ||
        std::get<OrderCancelledEvent>(cancelled.events.front().payload).order_id != id ||
        state.orders().contains(id)) {
        std::cerr << "Cancel command did not remove the persistent order\n";
        return false;
    }
    return true;
}

bool test_move_command_queues_range_order() {
    GameState state = order_state();
    CommandProcessor processor;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;

    const CommandResult queued = processor.execute(
        state, MoveArmyCommand{army_id, beta_a}
    );
    if (!queued.accepted || queued.events.size() != 1 ||
        queued.events.front().type != GameEventType::order_created ||
        state.find_army(army_id)->province_id != alpha_a ||
        state.find_army(army_id)->movement_points != 0 || state.orders().size() != 1) {
        std::cerr << "Move command did not queue a delayed range action\n";
        return false;
    }
    const OrderId order_id =
        std::get<OrderCreatedEvent>(queued.events.front().payload).order_id;
    const auto* order = std::get_if<ArmyActionOrder>(&state.orders().at(order_id));
    if (order == nullptr || order->path != std::vector<ProvinceId>{
            alpha_a, alpha_b, beta_a
        } || order->reserved_movement_half != 12 || !order->is_attack) {
        std::cerr << "Queued move lost its range path or attack surcharge\n";
        return false;
    }
    if (processor.execute(state, MoveArmyCommand{army_id, alpha_b}).accepted ||
        state.orders().size() != 1) {
        std::cerr << "Move command allowed a second order for one army\n";
        return false;
    }
    return true;
}

bool test_monthly_grant_respects_reserved_movement() {
    GameState state = order_state();
    CommandProcessor processor;
    OrderSystem system;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points =
        MovementSystem::maximum_movement_points_half(0);

    const OrderOperationResult queued =
        system.queue_army_action(state, army_id, {alpha_a, alpha_b, beta_a}, true);
    if (!queued.accepted || state.find_army(army_id)->movement_points != 0) return false;
    if (!processor.execute(state, AdvanceTurnCommand{1}).accepted ||
        state.find_army(army_id)->movement_points != 0) {
        std::cerr << "Monthly grant refilled movement already held by an action order\n";
        return false;
    }
    if (!system.cancel(state, *queued.order_id).accepted ||
        state.find_army(army_id)->movement_points !=
            MovementSystem::maximum_movement_points_half(0)) {
        std::cerr << "Cancelling after a monthly grant minted movement points\n";
        return false;
    }
    return true;
}

bool test_monthly_resolves_ordinary_movement_without_refund() {
    GameState state = order_state();
    OrderSystem orders;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!orders.queue_army_action(
            state, army_id, {alpha_a, alpha_b}, false
        ).accepted || state.find_army(army_id)->movement_points != 8) {
        return false;
    }

    const MonthlyOrderMovementReport report =
        MonthlyOrderSystem{}.resolve_movement(state);
    if (report.movements.size() != 1 || !report.refunds.empty() ||
        state.find_army(army_id)->province_id != alpha_b ||
        state.find_army(army_id)->movement_points != 8 || !state.orders().empty()) {
        std::cerr << "Monthly ordinary movement did not consume its queued route\n";
        return false;
    }
    return true;
}

bool test_monthly_refunds_invalidated_path_without_minting() {
    GameState state = order_state();
    OrderSystem orders;
    MovementSystem movement;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points =
        MovementSystem::maximum_movement_points_half(0);
    if (!orders.queue_army_action(
            state, army_id, {alpha_a, alpha_b, beta_a}, true
        ).accepted || state.find_army(army_id)->movement_points != 0) {
        return false;
    }
    [[maybe_unused]] const MonthlyMovementReport grant = movement.grant_monthly_points(state);
    state.set_occupation(alpha_b, CountryId{"beta"});

    const MonthlyOrderMovementReport report =
        MonthlyOrderSystem{}.resolve_movement(state);
    if (!report.movements.empty() || report.refunds.size() != 1 ||
        report.refunds.front().refunded_movement_half != 12 ||
        state.find_army(army_id)->province_id != alpha_a ||
        state.find_army(army_id)->movement_points !=
            MovementSystem::maximum_movement_points_half(0) ||
        !state.orders().empty()) {
        std::cerr << "Invalidated range path did not refund exactly its reservation\n";
        return false;
    }
    return true;
}

bool test_monthly_converts_friendly_attack_to_ordinary_movement() {
    GameState state = order_state();
    OrderSystem orders;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!orders.queue_army_action(
            state, army_id, {alpha_a, alpha_b, beta_a}, true
        ).accepted) {
        return false;
    }
    state.set_occupation(beta_a, CountryId{"alpha"});

    const MonthlyOrderMovementReport report =
        MonthlyOrderSystem{}.resolve_movement(state);
    if (report.movements.size() != 1 || !report.movements.front().converted_from_attack ||
        !report.refunds.empty() || state.find_army(army_id)->province_id != beta_a ||
        state.find_army(army_id)->movement_points != 4 || !state.orders().empty()) {
        std::cerr << "Friendly attack target was not converted with only its surcharge refunded\n";
        return false;
    }
    return true;
}

bool test_monthly_cancels_ordinary_move_that_becomes_hostile() {
    GameState state = order_state();
    OrderSystem orders;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!orders.queue_army_action(
            state, army_id, {alpha_a, alpha_b}, false
        ).accepted) {
        return false;
    }
    state.set_occupation(alpha_b, CountryId{"beta"});

    const MonthlyOrderMovementReport report =
        MonthlyOrderSystem{}.resolve_movement(state);
    if (!report.movements.empty() || report.refunds.size() != 1 ||
        state.find_army(army_id)->province_id != alpha_a ||
        state.find_army(army_id)->movement_points != 12 || !state.orders().empty()) {
        std::cerr << "Ordinary move into a newly hostile target was not cancelled\n";
        return false;
    }
    return true;
}

bool test_monthly_leaves_hostile_attack_for_combat_phase() {
    GameState state = order_state();
    OrderSystem orders;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!orders.queue_army_action(
            state, army_id, {alpha_a, alpha_b, beta_a}, true
        ).accepted) {
        return false;
    }

    const MonthlyOrderMovementReport report =
        MonthlyOrderSystem{}.resolve_movement(state);
    if (!report.movements.empty() || !report.refunds.empty() ||
        state.find_army(army_id)->province_id != alpha_a || state.orders().size() != 1) {
        std::cerr << "Movement phase executed an attack reserved for combat resolution\n";
        return false;
    }
    return true;
}

bool test_advance_turn_resolves_queued_ordinary_movement() {
    GameState state = order_state();
    CommandProcessor processor;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!processor.execute(state, MoveArmyCommand{army_id, alpha_b}).accepted ||
        state.find_army(army_id)->province_id != alpha_a || state.orders().size() != 1) {
        return false;
    }

    const CommandResult advanced = processor.execute(state, AdvanceTurnCommand{1});
    if (!advanced.accepted || state.find_army(army_id)->province_id != alpha_b ||
        !state.orders().empty() || state.find_army(army_id)->movement_points != 8) {
        std::cerr << "Advance turn did not resolve the queued ordinary move\n";
        return false;
    }
    return true;
}

bool test_auto_advance_queues_at_most_one_next_month_step() {
    GameState state = order_state();
    CommandProcessor processor;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ProvinceId beta_a{"beta_a"};
    state.set_occupation(beta_a, CountryId{"alpha"});
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    Army* army = state.find_army(army_id);
    army->movement_points = 12;
    army->advance_target = beta_a;

    if (!processor.execute(state, AdvanceTurnCommand{1}).accepted ||
        state.find_army(army_id)->province_id != alpha_a || state.orders().size() != 1) {
        std::cerr << "Auto advance moved immediately instead of creating one next-month order\n";
        return false;
    }
    const auto* first_order = std::get_if<ArmyActionOrder>(&state.orders().begin()->second);
    if (first_order == nullptr || first_order->destination != alpha_b ||
        first_order->path.size() != 2) {
        std::cerr << "Auto advance did not limit its first queued action to one step\n";
        return false;
    }

    if (!processor.execute(state, AdvanceTurnCommand{1}).accepted ||
        state.find_army(army_id)->province_id != alpha_b || state.orders().size() != 1) {
        std::cerr << "Auto advance did not execute one old step before queuing the next\n";
        return false;
    }
    const auto* second_order = std::get_if<ArmyActionOrder>(&state.orders().begin()->second);
    if (second_order == nullptr || second_order->origin != alpha_b ||
        second_order->destination != beta_a || second_order->path.size() != 2) {
        std::cerr << "Auto advance did not queue exactly one following-month step\n";
        return false;
    }
    return true;
}

bool test_pending_action_blocks_immediate_move_but_allows_rename() {
    GameState state = order_state();
    CommandProcessor processor;
    OrderSystem system;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!system.queue_army_action(state, army_id, {alpha_a, alpha_b}, false).accepted) {
        return false;
    }

    const CommandResult moved = processor.execute(state, MoveArmyCommand{army_id, alpha_b});
    if (moved.accepted || state.find_army(army_id)->province_id != alpha_a) {
        std::cerr << "Army with a pending action order moved immediately\n";
        return false;
    }
    const CommandResult renamed = processor.execute(state, RenameArmyCommand{army_id, 7});
    if (!renamed.accepted || state.find_army(army_id)->formation_number != 7) {
        std::cerr << "Pending action order incorrectly blocked army rename\n";
        return false;
    }
    return true;
}

bool test_pending_action_blocks_manual_merge() {
    GameState state = order_state();
    CommandProcessor processor;
    OrderSystem system;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId primary = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    const ArmyId secondary = state.create_army(CountryId{"alpha"}, alpha_a, 500);
    state.find_army(primary)->movement_points = 12;
    if (!system.queue_army_action(state, primary, {alpha_a, alpha_b}, false).accepted) {
        return false;
    }

    const CommandResult merge_primary = processor.execute(
        state, MergeArmiesCommand{primary, {secondary}}
    );
    if (merge_primary.accepted || state.find_army(primary) == nullptr ||
        state.find_army(secondary) == nullptr) {
        std::cerr << "Pending primary army was manually merged\n";
        return false;
    }

    GameState participant_state = order_state();
    const ArmyId participant_primary =
        participant_state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    const ArmyId ordered_participant =
        participant_state.create_army(CountryId{"alpha"}, alpha_a, 500);
    participant_state.find_army(ordered_participant)->movement_points = 12;
    if (!system.queue_army_action(
            participant_state, ordered_participant, {alpha_a, alpha_b}, false
        ).accepted) {
        return false;
    }
    const CommandResult merge_participant = processor.execute(
        participant_state,
        MergeArmiesCommand{participant_primary, {ordered_participant}}
    );
    if (merge_participant.accepted ||
        participant_state.find_army(participant_primary) == nullptr ||
        participant_state.find_army(ordered_participant) == nullptr) {
        std::cerr << "Pending merge participant was manually merged\n";
        return false;
    }
    return true;
}

bool test_validate_requires_army_at_order_origin() {
    GameState state = order_state();
    OrderSystem system;
    const ProvinceId alpha_a{"alpha_a"};
    const ProvinceId alpha_b{"alpha_b"};
    const ArmyId army_id = state.create_army(CountryId{"alpha"}, alpha_a, 1'000);
    state.find_army(army_id)->movement_points = 12;
    if (!system.queue_army_action(state, army_id, {alpha_a, alpha_b}, false).accepted) {
        return false;
    }
    state.find_army(army_id)->province_id = alpha_b;

    bool found_origin_issue = false;
    for (const std::string& issue : state.validate()) {
        if (issue.find("order origin") != std::string::npos) found_origin_issue = true;
    }
    if (!found_origin_issue) {
        std::cerr << "State validation accepted an army away from its order origin\n";
        return false;
    }
    return true;
}

} // namespace

bool run_order_system_tests() {
    return test_reachable_order_paths_and_costs() &&
        test_order_path_uses_weighted_dijkstra() &&
        test_order_path_tie_breaks_by_stable_province_id() &&
        test_queue_and_cancel_orders() &&
        test_attack_target_country_lock() &&
        test_rejects_debt_and_preserves_state_on_failure() &&
        test_command_processor_queues_and_cancels_projects() &&
        test_move_command_queues_range_order() &&
        test_monthly_grant_respects_reserved_movement() &&
        test_monthly_resolves_ordinary_movement_without_refund() &&
        test_monthly_refunds_invalidated_path_without_minting() &&
        test_monthly_converts_friendly_attack_to_ordinary_movement() &&
        test_monthly_cancels_ordinary_move_that_becomes_hostile() &&
        test_monthly_leaves_hostile_attack_for_combat_phase() &&
        test_advance_turn_resolves_queued_ordinary_movement() &&
        test_auto_advance_queues_at_most_one_next_month_step() &&
        test_pending_action_blocks_immediate_move_but_allows_rename() &&
        test_pending_action_blocks_manual_merge() &&
        test_validate_requires_army_at_order_origin();
}
