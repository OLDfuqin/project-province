#include "smoke_test_groups.hpp"

#include "province/core/army_system.hpp"
#include "province/core/command_processor.hpp"
#include "province/core/monthly_order_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/order_system.hpp"
#include "province/core/road_system.hpp"
#include "province/core/save_game.hpp"
#include "province/core/scenario_loader.hpp"
#include "province/core/technology_system.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <initializer_list>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace {

using Json = nlohmann::json;
using namespace province::core;

BattleSystem::RandomRoll fixed_rolls(std::initializer_list<std::int32_t> values) {
    auto data = std::make_shared<std::vector<std::int32_t>>(values);
    auto index = std::make_shared<std::size_t>(0);
    return [data, index]() {
        if (*index >= data->size()) throw std::logic_error{"fixed roll exhausted"};
        return data->at((*index)++);
    };
}

bool rejected(const Json& document, const std::string& suffix) {
    const auto path = std::filesystem::temp_directory_path() /
        ("province-invalid-save-" + suffix + ".json");
    {
        std::ofstream stream{path};
        stream << document.dump(2);
    }
    try {
        [[maybe_unused]] const auto loaded = SaveGameSerializer::load(path);
    } catch (const SaveGameError&) {
        std::filesystem::remove(path);
        return true;
    }
    std::filesystem::remove(path);
    return false;
}

std::optional<std::pair<ProvinceId, ProvinceId>> find_owned_connection(
    const GameState& state,
    const CountryId& country_id
) {
    for (const auto& [province_id, province] : state.provinces()) {
        if (state.controller_of(province_id) != country_id) continue;
        for (const ProvinceId& neighbor_id : province.neighbors) {
            if (state.controller_of(neighbor_id) == country_id &&
                state.road_level(province_id, neighbor_id) == RoadLevel::none) {
                return std::pair{province_id, neighbor_id};
            }
        }
    }
    return std::nullopt;
}

std::optional<std::array<ProvinceId, 3>> find_owned_chain(
    const GameState& state,
    const CountryId& country_id
) {
    for (const auto& [first_id, first] : state.provinces()) {
        if (state.controller_of(first_id) != country_id) continue;
        for (const ProvinceId& second_id : first.neighbors) {
            const Province* second = state.find_province(second_id);
            if (second == nullptr || state.controller_of(second_id) != country_id ||
                state.road_level(first_id, second_id) != RoadLevel::none) {
                continue;
            }
            for (const ProvinceId& third_id : second->neighbors) {
                if (third_id == first_id || state.controller_of(third_id) != country_id ||
                    state.road_level(second_id, third_id) != RoadLevel::none) {
                    continue;
                }
                return std::array{first_id, second_id, third_id};
            }
        }
    }
    return std::nullopt;
}

template <typename OrderType>
const OrderType* find_order(const GameState& state) {
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        if (const auto* typed = std::get_if<OrderType>(&order)) return typed;
    }
    return nullptr;
}

std::size_t order_index(const Json& document, const std::string& type) {
    const Json& orders = document.at("orders");
    for (std::size_t index = 0; index < orders.size(); ++index) {
        if (orders[index].at("type") == type) return index;
    }
    throw std::runtime_error{"saved order type was not found: " + type};
}

const Json& province_document(const Json& document, const std::string& province_id) {
    for (const Json& province : document.at("provinces")) {
        if (province.at("id") == province_id) return province;
    }
    throw std::runtime_error{"saved province was not found: " + province_id};
}

std::size_t foreign_order_count(const GameState& state, const CountryId& human) {
    std::size_t count = 0;
    for (const auto& [id, order] : state.orders()) {
        static_cast<void>(id);
        const CountryId country_id = std::visit([](const auto& typed_order) {
            return typed_order.country_id;
        }, order);
        if (country_id != human) ++count;
    }
    return count;
}

bool test_schema7_round_trip_restores_every_order_without_recharging() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const CountryId human{"auroria"};
    const CountryId ai{"caelus"};
    const CountryId defender{"verdantia"};
    CountryTechnology* technology = state.find_technology(human);
    if (technology == nullptr) return false;
    technology->roads_level = CountryTechnology::roads_maximum_level;

    OrderSystem orders;
    const OrderOperationResult research =
        orders.queue_research(state, human, TechnologyTrack::economy);
    if (!research.accepted || !research.order_id.has_value()) return false;
    const MonthlyOrderProjectReport first_research_tick =
        MonthlyOrderSystem{}.resolve_projects(state);
    if (!first_research_tick.research.empty()) return false;

    const auto connection = find_owned_connection(state, human);
    if (!connection.has_value()) {
        std::cerr << "No owned connection is available for schema 7 test setup\n";
        return false;
    }
    const ProvinceId origin = connection->first;
    const ProvinceId destination = connection->second;
    technology->roads_level = RoadSystem::required_roads_level(
        state.find_province(origin)->terrain,
        state.find_province(destination)->terrain
    );
    const ArmyId army_id = state.create_army(human, origin, 2'000);
    Army* army = state.find_army(army_id);
    const std::int32_t initial_movement =
        MovementSystem::maximum_movement_points_half(technology->military_level);
    army->movement_points = initial_movement;

    const OrderOperationResult movement =
        orders.queue_army_action(state, army_id, {origin, destination}, false);
    const OrderOperationResult recruitment =
        orders.queue_recruitment(state, human, origin, 100);
    const OrderOperationResult road =
        orders.queue_road_construction(state, human, origin, destination);
    const OrderOperationResult declaration =
        orders.queue_war_declaration(state, ai, defender);
    if (!movement.accepted || !recruitment.accepted || !road.accepted ||
        !declaration.accepted || state.orders().size() != 5) {
        std::cerr << "Could not create every schema 7 order variant\n";
        return false;
    }

    const std::int64_t treasury_after_prepayment = state.find_country(human)->treasury;
    const std::int32_t movement_after_reservation = state.find_army(army_id)->movement_points;
    const std::int32_t reserved_movement = initial_movement - movement_after_reservation;
    const std::int64_t population_before_completion = state.find_province(origin)->population;
    const std::int64_t recruitable_before_completion =
        state.find_province(origin)->recruitable_population;
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-orders.json";
    SaveGameSerializer::save(path, state, 42, human, human);

    std::ifstream stream{path};
    const Json document = Json::parse(stream);
    stream.close();
    if (document.at("schema_version") != 7 ||
        document.at("next_order_sequence") != 6 ||
        document.at("orders").size() != 5 ||
        order_index(document, "army_action") >= document.at("orders").size() ||
        order_index(document, "recruitment") >= document.at("orders").size() ||
        order_index(document, "road_construction") >= document.at("orders").size() ||
        order_index(document, "research") >= document.at("orders").size() ||
        order_index(document, "war_declaration") >= document.at("orders").size()) {
        std::cerr << "Schema 7 did not serialize the order queue and sequence\n";
        std::filesystem::remove(path);
        return false;
    }

    LoadedGame loaded{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        loaded = SaveGameSerializer::load(path);
    } catch (const SaveGameError& error) {
        std::cerr << "Schema 7 order load failed: " << error.what() << "\n";
        std::filesystem::remove(path);
        return false;
    }
    std::filesystem::remove(path);

    const ArmyActionOrder* loaded_action = find_order<ArmyActionOrder>(loaded.state);
    const RecruitmentOrder* loaded_recruitment = find_order<RecruitmentOrder>(loaded.state);
    const RoadConstructionOrder* loaded_road = find_order<RoadConstructionOrder>(loaded.state);
    const ResearchOrder* loaded_research = find_order<ResearchOrder>(loaded.state);
    const WarDeclarationOrder* loaded_declaration = find_order<WarDeclarationOrder>(loaded.state);
    if (loaded.next_event_sequence != 42 || loaded.player_country_id != human ||
        !loaded.ai_human_country_id.has_value() ||
        *loaded.ai_human_country_id != human || loaded.state.orders().size() != 5 ||
        loaded_action == nullptr || loaded_recruitment == nullptr ||
        loaded_road == nullptr || loaded_research == nullptr ||
        loaded_declaration == nullptr || loaded_action->army_id != army_id ||
        loaded_action->path != std::vector<ProvinceId>{origin, destination} ||
        loaded_action->reserved_movement_half != reserved_movement ||
        loaded_recruitment->manpower != 100 || loaded_recruitment->paid_cost != 400 ||
        loaded_recruitment->remaining_months != 1 ||
        loaded_road->province_a != origin || loaded_road->province_b != destination ||
        loaded_road->remaining_months != 1 || loaded_research->previous_level != 0 ||
        loaded_research->target_level != 1 || loaded_research->remaining_months != 1 ||
        loaded_declaration->country_id != ai || loaded_declaration->defender_id != defender ||
        loaded.state.find_country(human)->treasury != treasury_after_prepayment ||
        loaded.state.find_army(army_id)->movement_points != movement_after_reservation ||
        loaded.state.find_province(origin)->population != population_before_completion ||
        loaded.state.find_province(origin)->recruitable_population != recruitable_before_completion ||
        !loaded.state.validate().empty()) {
        std::cerr << "Schema 7 order fields or reserved resources did not round trip\n";
        return false;
    }

    GameState expected_after_turn = state;
    GameState loaded_after_turn = loaded.state;
    CommandProcessor expected_processor;
    CommandProcessor loaded_processor;
    expected_processor.enable_ai(human);
    loaded_processor.enable_ai(human);
    const std::size_t expected_orders_before_restore = expected_after_turn.orders().size();
    const std::size_t loaded_orders_before_restore = loaded_after_turn.orders().size();
    expected_processor.enable_ai(expected_after_turn, human);
    loaded_processor.enable_ai(loaded_after_turn, human);
    if (expected_after_turn.orders().size() != expected_orders_before_restore ||
        loaded_after_turn.orders().size() != loaded_orders_before_restore) {
        std::cerr << "Restoring AI configuration queued duplicate initial orders\n";
        return false;
    }
    const CommandResult expected_turn = expected_processor.execute(
        expected_after_turn, AdvanceTurnCommand{1}
    );
    const CommandResult loaded_turn = loaded_processor.execute(
        loaded_after_turn, AdvanceTurnCommand{1}
    );
    const auto expected_path = std::filesystem::temp_directory_path() /
        "province-schema7-expected-after-turn.json";
    const auto loaded_path = std::filesystem::temp_directory_path() /
        "province-schema7-loaded-after-turn.json";
    if (!expected_turn.accepted || !loaded_turn.accepted) return false;
    SaveGameSerializer::save(expected_path, expected_after_turn, 100, human, human);
    SaveGameSerializer::save(loaded_path, loaded_after_turn, 100, human, human);
    std::ifstream expected_stream{expected_path};
    std::ifstream loaded_stream{loaded_path};
    const Json expected_document = Json::parse(expected_stream);
    const Json loaded_document = Json::parse(loaded_stream);
    expected_stream.close();
    loaded_stream.close();
    std::filesystem::remove(expected_path);
    std::filesystem::remove(loaded_path);
    bool equivalent_events = expected_turn.events.size() == loaded_turn.events.size();
    for (std::size_t index = 0; equivalent_events && index < expected_turn.events.size(); ++index) {
        equivalent_events = expected_turn.events[index].sequence ==
                loaded_turn.events[index].sequence &&
            expected_turn.events[index].type == loaded_turn.events[index].type;
    }
    const std::size_t expected_foreign_orders = foreign_order_count(expected_after_turn, human);
    const std::size_t loaded_foreign_orders = foreign_order_count(loaded_after_turn, human);
    if (loaded_document != expected_document || !equivalent_events ||
        expected_foreign_orders == 0 ||
        loaded_foreign_orders != expected_foreign_orders) {
        std::cerr << "Loaded order queue and AI did not resolve like the pre-save state\n";
        return false;
    }
    const std::size_t expected_orders_after_plan = expected_after_turn.orders().size();
    const std::size_t loaded_orders_after_plan = loaded_after_turn.orders().size();
    expected_processor.enable_ai(expected_after_turn, human);
    loaded_processor.enable_ai(loaded_after_turn, human);
    if (expected_after_turn.orders().size() != expected_orders_after_plan ||
        loaded_after_turn.orders().size() != loaded_orders_after_plan) {
        std::cerr << "AI configuration repeated next-month planning after settlement\n";
        return false;
    }

    const std::size_t order_count_before_ai_restore = loaded.state.orders().size();
    CommandProcessor restored_processor;
    restored_processor.enable_ai(*loaded.ai_human_country_id);
    if (!restored_processor.ai_enabled() ||
        loaded.state.orders().size() != order_count_before_ai_restore) {
        std::cerr << "Restoring saved AI configuration duplicated initial AI orders\n";
        return false;
    }

    const OrderId recruitment_id = loaded_recruitment->id;
    const std::int64_t recruitment_paid_cost = loaded_recruitment->paid_cost;
    const ProvinceId recruitment_province = loaded_recruitment->province_id;
    const std::int64_t treasury_before_cancel = loaded.state.find_country(human)->treasury;
    if (!orders.cancel(loaded.state, recruitment_id).accepted ||
        loaded.state.find_country(human)->treasury !=
            treasury_before_cancel + recruitment_paid_cost) {
        std::cerr << "Loaded prepaid recruitment could not be refunded exactly once\n";
        return false;
    }
    const OrderOperationResult requeued =
        orders.queue_recruitment(loaded.state, human, recruitment_province, 100);
    if (!requeued.accepted || !requeued.order_id.has_value() ||
        requeued.order_id->value() != "order_6" ||
        loaded.state.find_country(human)->treasury != treasury_before_cancel) {
        std::cerr << "Loaded next order sequence did not continue without recharging\n";
        return false;
    }
    return true;
}

bool test_schema7_rejects_old_versions_and_malformed_orders() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const CountryId human{"auroria"};
    CountryTechnology* technology = state.find_technology(human);
    technology->roads_level = CountryTechnology::roads_maximum_level;
    OrderSystem orders;
    if (!orders.queue_research(state, human, TechnologyTrack::economy).accepted) return false;
    static_cast<void>(MonthlyOrderSystem{}.resolve_projects(state));
    const auto connection = find_owned_connection(state, human);
    if (!connection.has_value()) return false;
    const ArmyId army_id = state.create_army(human, connection->first, 2'000);
    state.find_army(army_id)->movement_points =
        MovementSystem::maximum_movement_points_half(technology->military_level);
    if (!orders.queue_army_action(
            state, army_id, {connection->first, connection->second}, false
        ).accepted ||
        !orders.queue_recruitment(state, human, connection->first, 100).accepted ||
        !orders.queue_road_construction(
            state, human, connection->first, connection->second
        ).accepted ||
        !orders.queue_war_declaration(
            state, CountryId{"caelus"}, CountryId{"verdantia"}
        ).accepted) {
        return false;
    }
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-malformed-base.json";
    SaveGameSerializer::save(path, state, 12, human, human);
    std::ifstream stream{path};
    const Json document = Json::parse(stream);
    stream.close();
    std::filesystem::remove(path);

    const std::size_t action_index = order_index(document, "army_action");
    const std::size_t recruitment_index = order_index(document, "recruitment");
    const std::size_t road_index = order_index(document, "road_construction");
    const std::size_t research_index = order_index(document, "research");
    const std::size_t declaration_index = order_index(document, "war_declaration");

    Json schema6 = document;
    schema6["schema_version"] = 6;
    Json unknown_root = document;
    unknown_root["executable_payload"] = "reject unknown schema fields";
    Json unknown_country_field = document;
    unknown_country_field["countries"][0]["executable_payload"] = "reject nested fields";
    Json unknown_clock_field = document;
    unknown_clock_field["clock"]["day"] = 1;
    Json missing_orders = document;
    missing_orders.erase("orders");
    Json missing_technology = document;
    missing_technology["technologies"].erase(
        missing_technology["technologies"].begin()
    );
    Json bad_next_sequence = document;
    bad_next_sequence["next_order_sequence"] = 1;
    Json exhausted_next_sequence = document;
    exhausted_next_sequence["next_order_sequence"] =
        std::numeric_limits<std::uint64_t>::max();
    Json duplicate_next_army_sequence = document;
    duplicate_next_army_sequence["next_army_sequence"] = 1;
    Json exhausted_next_army_sequence = document;
    exhausted_next_army_sequence["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max();
    Json recruitment_with_no_army_capacity = document;
    recruitment_with_no_army_capacity["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 1;
    Json exhausted_next_event_sequence = document;
    exhausted_next_event_sequence["next_event_sequence"] =
        std::numeric_limits<std::int64_t>::max();
    Json unsigned_only_next_event_sequence = document;
    unsigned_only_next_event_sequence["next_event_sequence"] =
        std::numeric_limits<std::uint64_t>::max();
    Json extreme_military_level = document;
    for (Json& technology_entry : extreme_military_level["technologies"]) {
        if (technology_entry.at("country_id") == human.value()) {
            technology_entry["military_level"] =
                std::numeric_limits<std::int32_t>::max();
        }
    }
    Json duplicate_id = document;
    duplicate_id["orders"].push_back(duplicate_id["orders"][action_index]);
    Json duplicate_army_order = document;
    Json second_action = duplicate_army_order["orders"][action_index];
    second_action["id"] = "order_6";
    duplicate_army_order["orders"].push_back(std::move(second_action));
    duplicate_army_order["next_order_sequence"] = 7;
    Json unknown_type = document;
    unknown_type["orders"][action_index]["type"] = "execute_script";
    Json unknown_order_field = document;
    unknown_order_field["orders"][action_index]["payload"] = "unexpected";

    Json unknown_army = document;
    unknown_army["orders"][action_index]["army_id"] = "missing_army";
    Json wrong_action_owner = document;
    wrong_action_owner["orders"][action_index]["country_id"] = "caelus";
    Json hidden_neutral_action = document;
    hidden_neutral_action["orders"][action_index]["country_id"] = "neutral";
    const std::string action_army_id =
        hidden_neutral_action["orders"][action_index]["army_id"].get<std::string>();
    for (Json& army : hidden_neutral_action["armies"]) {
        if (army.at("id") == action_army_id) {
            army["owner_id"] = "neutral";
            break;
        }
    }
    Json reserved_guard_id_owned_by_normal_country = document;
    const std::string reserved_action_army_id =
        reserved_guard_id_owned_by_normal_country["orders"][action_index]
            ["army_id"].get<std::string>();
    for (Json& army : reserved_guard_id_owned_by_normal_country["armies"]) {
        if (army.at("id") != reserved_action_army_id) continue;
        const std::string forged_id = "neutral_guard_" +
            army.at("province_id").get<std::string>();
        army["id"] = forged_id;
        reserved_guard_id_owned_by_normal_country["orders"][action_index]
            ["army_id"] = forged_id;
        break;
    }
    Json reserved_guard_id_in_wrong_province = document;
    std::size_t first_neutral_army = reserved_guard_id_in_wrong_province["armies"].size();
    std::size_t second_neutral_army = reserved_guard_id_in_wrong_province["armies"].size();
    for (std::size_t index = 0;
         index < reserved_guard_id_in_wrong_province["armies"].size();
         ++index) {
        if (reserved_guard_id_in_wrong_province["armies"][index].at("owner_id") !=
            "neutral") continue;
        if (first_neutral_army == reserved_guard_id_in_wrong_province["armies"].size()) {
            first_neutral_army = index;
        } else {
            second_neutral_army = index;
            break;
        }
    }
    if (first_neutral_army == reserved_guard_id_in_wrong_province["armies"].size() ||
        second_neutral_army == reserved_guard_id_in_wrong_province["armies"].size()) {
        return false;
    }
    reserved_guard_id_in_wrong_province["armies"][first_neutral_army]["id"] =
        "neutral_guard_" +
        reserved_guard_id_in_wrong_province["armies"][second_neutral_army]
            .at("province_id").get<std::string>();
    Json broken_path = document;
    broken_path["orders"][action_index]["path"][1] = "capital_caelus";
    broken_path["orders"][action_index]["destination"] = "capital_caelus";
    Json forged_movement = document;
    forged_movement["orders"][action_index]["reserved_movement_half"] = 1;

    Json forged_recruitment_cost = document;
    forged_recruitment_cost["orders"][recruitment_index]["paid_cost"] = 1;
    Json fractional_recruitment_cost = document;
    fractional_recruitment_cost["orders"][recruitment_index]["paid_cost"] = 400.5;
    Json over_reserved_population = document;
    const std::string recruitment_province_id =
        document["orders"][recruitment_index]["province_id"].get<std::string>();
    const Json& recruitment_province = province_document(document, recruitment_province_id);
    const std::int64_t recruitment_capacity = std::min(
        recruitment_province.at("population").get<std::int64_t>(),
        recruitment_province.at("recruitable_population").get<std::int64_t>()
    );
    const std::int64_t individually_excessive_manpower = recruitment_capacity + 1;
    over_reserved_population["orders"][recruitment_index]["manpower"] =
        individually_excessive_manpower;
    over_reserved_population["orders"][recruitment_index]["paid_cost"] =
        individually_excessive_manpower * ArmySystem::recruitment_cost_per_soldier;
    Json cumulatively_over_reserved_population = document;
    Json second_recruitment =
        cumulatively_over_reserved_population["orders"][recruitment_index];
    second_recruitment["id"] = "order_6";
    second_recruitment["manpower"] = recruitment_capacity;
    second_recruitment["paid_cost"] =
        recruitment_capacity * ArmySystem::recruitment_cost_per_soldier;
    cumulatively_over_reserved_population["orders"].push_back(
        std::move(second_recruitment)
    );
    cumulatively_over_reserved_population["next_order_sequence"] = 7;
    Json cumulatively_over_reserved_army_capacity = document;
    Json capacity_recruitment =
        cumulatively_over_reserved_army_capacity["orders"][recruitment_index];
    capacity_recruitment["id"] = "order_6";
    capacity_recruitment["manpower"] = 1;
    capacity_recruitment["paid_cost"] = ArmySystem::recruitment_cost_per_soldier;
    cumulatively_over_reserved_army_capacity["orders"].push_back(
        std::move(capacity_recruitment)
    );
    cumulatively_over_reserved_army_capacity["next_order_sequence"] = 7;
    cumulatively_over_reserved_army_capacity["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 2;
    Json unknown_recruitment_province = document;
    unknown_recruitment_province["orders"][recruitment_index]["province_id"] =
        "missing_province";

    Json forged_road_cost = document;
    forged_road_cost["orders"][road_index]["paid_cost"] = 1;
    Json future_road_technology_cost = document;
    const std::string road_a =
        future_road_technology_cost["orders"][road_index]["province_a"].get<std::string>();
    const std::string road_b =
        future_road_technology_cost["orders"][road_index]["province_b"].get<std::string>();
    const TerrainType road_a_terrain = terrain_from_string(
        province_document(future_road_technology_cost, road_a).at("terrain").get<std::string>()
    );
    const TerrainType road_b_terrain = terrain_from_string(
        province_document(future_road_technology_cost, road_b).at("terrain").get<std::string>()
    );
    const std::int32_t road_minimum_level = RoadSystem::required_roads_level(
        road_a_terrain, road_b_terrain
    );
    for (Json& technology_entry : future_road_technology_cost["technologies"]) {
        if (technology_entry.at("country_id") == human.value()) {
            technology_entry["roads_level"] = road_minimum_level;
        }
    }
    const std::int64_t road_base_cost = RoadSystem::endpoint_base_cost(road_a_terrain) +
        RoadSystem::endpoint_base_cost(road_b_terrain);
    future_road_technology_cost["orders"][road_index]["paid_cost"] = road_base_cost *
        (100 - RoadSystem::discount_percent(road_minimum_level + 1)) / 100;
    Json invalid_road_target = document;
    invalid_road_target["orders"][road_index]["province_b"] =
        invalid_road_target["orders"][road_index]["province_a"];

    Json unknown_track = document;
    unknown_track["orders"][research_index]["track"] = "alchemy";
    Json forged_research_cost = document;
    forged_research_cost["orders"][research_index]["paid_cost"] = 1;
    Json invalid_research_progress = document;
    invalid_research_progress["orders"][research_index]["remaining_months"] = 0;
    Json extreme_previous_level = document;
    extreme_previous_level["orders"][research_index]["previous_level"] =
        std::numeric_limits<std::int32_t>::max();
    Json research_level_regression = document;
    research_level_regression["orders"][research_index]["previous_level"] = 1;
    research_level_regression["orders"][research_index]["target_level"] = 2;
    research_level_regression["orders"][research_index]["paid_cost"] =
        TechnologySystem::research_cost(1);
    research_level_regression["orders"][research_index]["remaining_months"] = 1;
    Json duplicate_research = document;
    Json second_research = duplicate_research["orders"][research_index];
    second_research["id"] = "order_6";
    duplicate_research["orders"].push_back(std::move(second_research));
    duplicate_research["next_order_sequence"] = 7;

    Json unknown_war_target = document;
    unknown_war_target["orders"][declaration_index]["defender_id"] = "missing_country";
    Json duplicate_war = document;
    Json second_war = duplicate_war["orders"][declaration_index];
    second_war["id"] = "order_6";
    std::swap(second_war["country_id"], second_war["defender_id"]);
    duplicate_war["orders"].push_back(std::move(second_war));
    duplicate_war["next_order_sequence"] = 7;

    const std::pair<const Json*, const char*> malformed[] = {
        {&schema6, "schema6"},
        {&unknown_root, "unknown-root"},
        {&unknown_country_field, "unknown-country-field"},
        {&unknown_clock_field, "unknown-clock-field"},
        {&missing_orders, "missing-orders"},
        {&missing_technology, "missing-technology"},
        {&bad_next_sequence, "bad-next-sequence"},
        {&exhausted_next_sequence, "exhausted-next-sequence"},
        {&duplicate_next_army_sequence, "duplicate-next-army-sequence"},
        {&exhausted_next_army_sequence, "exhausted-next-army-sequence"},
        {&recruitment_with_no_army_capacity, "recruitment-with-no-army-capacity"},
        {&exhausted_next_event_sequence, "exhausted-next-event-sequence"},
        {&unsigned_only_next_event_sequence, "unsigned-next-event-sequence"},
        {&extreme_military_level, "extreme-military-level"},
        {&duplicate_id, "duplicate-order-id"},
        {&duplicate_army_order, "duplicate-army-order"},
        {&unknown_type, "unknown-order-type"},
        {&unknown_order_field, "unknown-order-field"},
        {&unknown_army, "unknown-army"},
        {&wrong_action_owner, "wrong-action-owner"},
        {&hidden_neutral_action, "hidden-neutral-action"},
        {&reserved_guard_id_owned_by_normal_country,
         "reserved-guard-id-owned-by-normal-country"},
        {&reserved_guard_id_in_wrong_province, "reserved-guard-id-in-wrong-province"},
        {&broken_path, "broken-path"},
        {&forged_movement, "forged-movement"},
        {&forged_recruitment_cost, "forged-recruitment-cost"},
        {&fractional_recruitment_cost, "fractional-recruitment-cost"},
        {&over_reserved_population, "over-reserved-population"},
        {&cumulatively_over_reserved_population, "cumulative-over-reserved-population"},
        {&cumulatively_over_reserved_army_capacity,
         "cumulative-over-reserved-army-capacity"},
        {&unknown_recruitment_province, "unknown-recruitment-province"},
        {&forged_road_cost, "forged-road-cost"},
        {&future_road_technology_cost, "future-road-technology-cost"},
        {&invalid_road_target, "invalid-road-target"},
        {&unknown_track, "unknown-track"},
        {&forged_research_cost, "forged-research-cost"},
        {&invalid_research_progress, "invalid-research-progress"},
        {&extreme_previous_level, "extreme-previous-level"},
        {&research_level_regression, "research-level-regression"},
        {&duplicate_research, "duplicate-research"},
        {&unknown_war_target, "unknown-war-target"},
        {&duplicate_war, "duplicate-war"},
    };
    for (const auto& [candidate, suffix] : malformed) {
        if (!rejected(*candidate, suffix)) {
            std::cerr << "Schema 7 accepted malformed save case: " << suffix << "\n";
            return false;
        }
    }

    Json last_safe_sequence = document;
    last_safe_sequence["next_order_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 1;
    const auto exhausted_path = std::filesystem::temp_directory_path() /
        "province-schema7-near-exhausted-orders.json";
    {
        std::ofstream exhausted_stream{exhausted_path};
        exhausted_stream << last_safe_sequence.dump(2);
    }
    LoadedGame exhausted{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        exhausted = SaveGameSerializer::load(exhausted_path);
    } catch (const SaveGameError& error) {
        std::cerr << "Last safe order sequence did not load: " << error.what() << "\n";
        std::filesystem::remove(exhausted_path);
        return false;
    }
    std::filesystem::remove(exhausted_path);
    const std::size_t orders_before_exhausted_queue = exhausted.state.orders().size();
    const std::int64_t treasury_before_exhausted_queue =
        exhausted.state.find_country(human)->treasury;
    const OrderOperationResult exhausted_queue = orders.queue_recruitment(
        exhausted.state,
        human,
        ProvinceId{recruitment_province_id},
        1
    );
    if (exhausted_queue.accepted ||
        exhausted.state.orders().size() != orders_before_exhausted_queue ||
        exhausted.state.find_country(human)->treasury != treasury_before_exhausted_queue) {
        std::cerr << "Exhausted order allocator wrapped or mutated prepaid resources\n";
        return false;
    }

    Json two_remaining_army_slots = document;
    two_remaining_army_slots["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 3;
    const auto two_slots_path = std::filesystem::temp_directory_path() /
        "province-schema7-two-remaining-army-slots.json";
    {
        std::ofstream two_slots_stream{two_slots_path};
        two_slots_stream << two_remaining_army_slots.dump(2);
    }
    LoadedGame two_slots{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        two_slots = SaveGameSerializer::load(two_slots_path);
    } catch (const SaveGameError& error) {
        std::cerr << "Two remaining army slots did not load: " << error.what() << "\n";
        std::filesystem::remove(two_slots_path);
        return false;
    }
    std::filesystem::remove(two_slots_path);
    const OrderOperationResult second_reserved_army = orders.queue_recruitment(
        two_slots.state, human, ProvinceId{recruitment_province_id}, 1
    );
    const std::size_t two_orders_at_capacity = two_slots.state.orders().size();
    const std::int64_t two_slots_treasury_at_capacity =
        two_slots.state.find_country(human)->treasury;
    const OrderOperationResult third_reserved_army = orders.queue_recruitment(
        two_slots.state, human, ProvinceId{recruitment_province_id}, 1
    );
    if (!second_reserved_army.accepted || third_reserved_army.accepted ||
        two_slots.state.orders().size() != two_orders_at_capacity ||
        two_slots.state.find_country(human)->treasury !=
            two_slots_treasury_at_capacity ||
        !two_slots.state.validate().empty()) {
        std::cerr << "Multiple recruitment orders did not reserve army ID slots exactly\n";
        return false;
    }

    Json last_safe_army = document;
    std::string missing_neutral_guard_province;
    for (auto iterator = last_safe_army["armies"].begin();
         iterator != last_safe_army["armies"].end();
         ++iterator) {
        if (iterator->at("owner_id") != "neutral") continue;
        missing_neutral_guard_province =
            iterator->at("province_id").get<std::string>();
        last_safe_army["armies"].erase(iterator);
        break;
    }
    if (missing_neutral_guard_province.empty()) return false;
    last_safe_army["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 2;
    const auto army_exhausted_path = std::filesystem::temp_directory_path() /
        "province-schema7-near-exhausted-armies.json";
    {
        std::ofstream exhausted_stream{army_exhausted_path};
        exhausted_stream << last_safe_army.dump(2);
    }
    LoadedGame army_exhausted{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        army_exhausted = SaveGameSerializer::load(army_exhausted_path);
    } catch (const SaveGameError& error) {
        std::cerr << "Last allocatable army sequence did not load: "
                  << error.what() << "\n";
        std::filesystem::remove(army_exhausted_path);
        return false;
    }
    std::filesystem::remove(army_exhausted_path);
    const std::size_t armies_before_exhaustion = army_exhausted.state.armies().size();
    const std::size_t orders_before_capacity_rejection =
        army_exhausted.state.orders().size();
    const std::int64_t treasury_before_capacity_rejection =
        army_exhausted.state.find_country(human)->treasury;
    const OrderOperationResult reserved_capacity_rejection =
        orders.queue_recruitment(
            army_exhausted.state,
            human,
            ProvinceId{recruitment_province_id},
            1
        );
    if (reserved_capacity_rejection.accepted ||
        army_exhausted.state.orders().size() != orders_before_capacity_rejection ||
        army_exhausted.state.find_country(human)->treasury !=
            treasury_before_capacity_rejection) {
        std::cerr << "Pending recruitment did not reserve the last army ID slot\n";
        return false;
    }

    const auto pending_recruitment = std::find_if(
        army_exhausted.state.orders().begin(),
        army_exhausted.state.orders().end(),
        [](const auto& entry) {
            return std::holds_alternative<RecruitmentOrder>(entry.second);
        }
    );
    if (pending_recruitment == army_exhausted.state.orders().end() ||
        !orders.cancel(army_exhausted.state, pending_recruitment->first).accepted) {
        std::cerr << "Could not cancel the recruitment reserving army ID capacity\n";
        return false;
    }
    const OrderOperationResult final_recruitment = orders.queue_recruitment(
        army_exhausted.state,
        human,
        ProvinceId{recruitment_province_id},
        1
    );
    if (!final_recruitment.accepted || !final_recruitment.order_id.has_value()) {
        std::cerr << "Cancelling recruitment did not release army ID capacity\n";
        return false;
    }
    const std::int32_t month_before_final_recruitment =
        army_exhausted.state.clock().month();
    const CommandResult final_turn = CommandProcessor{}.execute(
        army_exhausted.state, AdvanceTurnCommand{1}
    );
    const auto final_recruitment_event = std::find_if(
        final_turn.events.begin(), final_turn.events.end(),
        [](const GameEvent& event) {
            return event.type == GameEventType::army_recruited;
        }
    );
    const ArmyId expected_final_army{
        "army_" + std::to_string(std::numeric_limits<std::uint64_t>::max() - 2)
    };
    const ArmyId expected_rebuilt_guard{
        "neutral_guard_" + missing_neutral_guard_province
    };
    const Army* rebuilt_guard =
        army_exhausted.state.find_army(expected_rebuilt_guard);
    if (!final_turn.accepted ||
        final_recruitment_event == final_turn.events.end() ||
        std::get<ArmyRecruitedEvent>(final_recruitment_event->payload).order_id !=
            *final_recruitment.order_id ||
        std::get<ArmyRecruitedEvent>(final_recruitment_event->payload).army_id !=
            expected_final_army ||
        army_exhausted.state.clock().month() != month_before_final_recruitment + 1 ||
        army_exhausted.state.find_army(expected_final_army) == nullptr ||
        rebuilt_guard == nullptr || rebuilt_guard->owner_id != CountryId{"neutral"} ||
        rebuilt_guard->province_id != ProvinceId{missing_neutral_guard_province} ||
        army_exhausted.state.armies().size() != armies_before_exhaustion + 2 ||
        !army_exhausted.state.validate().empty()) {
        std::cerr << "Neutral rebuild consumed the final ordinary recruitment ID slot\n";
        return false;
    }
    const auto rebuilt_guard_path = std::filesystem::temp_directory_path() /
        "province-schema7-rebuilt-neutral-guard.json";
    SaveGameSerializer::save(
        rebuilt_guard_path, army_exhausted.state, 100, human, std::nullopt
    );
    LoadedGame rebuilt_guard_round_trip = SaveGameSerializer::load(rebuilt_guard_path);
    std::filesystem::remove(rebuilt_guard_path);
    if (rebuilt_guard_round_trip.state.find_army(expected_rebuilt_guard) == nullptr ||
        rebuilt_guard_round_trip.state.find_army(expected_final_army) == nullptr ||
        !rebuilt_guard_round_trip.state.validate().empty()) {
        std::cerr << "Deterministic neutral guard did not round trip with final army ID\n";
        return false;
    }
    return true;
}

bool test_neutral_guard_rebuild_survives_exhaustion_after_mutual_combat() {
    const CountryId human{"auroria"};
    const CountryId neutral{"neutral"};
    const ProvinceId origin{"cell_4_4"};
    const ProvinceId target{"cell_5_4"};
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1000, 1},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    Province* neutral_province = state.find_province(target);
    if (neutral_province == nullptr) return false;
    neutral_province->population = 1;
    neutral_province->population_growth_remainder = 9'980;
    ArmyId original_guard{"missing"};
    for (const auto& [army_id, army] : state.armies()) {
        if (army.owner_id == neutral && army.province_id == target) {
            original_guard = army_id;
            break;
        }
    }
    Army* guard = state.find_army(original_guard);
    if (guard == nullptr) return false;
    guard->manpower = 1;
    const ArmyId attacker = state.create_army(human, origin, 1);
    state.find_army(attacker)->movement_points = 12;
    OrderSystem orders;
    const OrderOperationResult attack = orders.queue_army_action(
        state, attacker, {origin, target}, true
    );
    const OrderOperationResult recruitment = orders.queue_recruitment(
        state, human, origin, 1
    );
    if (!attack.accepted || !recruitment.accepted ||
        !recruitment.order_id.has_value()) return false;

    const auto setup_path = std::filesystem::temp_directory_path() /
        "province-schema7-neutral-combat-army-exhaustion.json";
    SaveGameSerializer::save(setup_path, state, 1, human, std::nullopt);
    std::ifstream stream{setup_path};
    Json document = Json::parse(stream);
    stream.close();
    document["next_army_sequence"] =
        std::numeric_limits<std::uint64_t>::max() - 2;
    {
        std::ofstream rewritten{setup_path};
        rewritten << document.dump(2);
    }
    LoadedGame loaded = SaveGameSerializer::load(setup_path);
    std::filesystem::remove(setup_path);

    CommandProcessor processor{fixed_rolls({7, 7})};
    const CommandResult combat_turn = processor.execute(
        loaded.state, AdvanceTurnCommand{1}
    );
    const ArmyId final_ordinary_army{
        "army_" + std::to_string(std::numeric_limits<std::uint64_t>::max() - 2)
    };
    if (!combat_turn.accepted || loaded.state.find_army(attacker) != nullptr ||
        loaded.state.find_army(original_guard) != nullptr ||
        loaded.state.find_province(target)->owner_id != neutral ||
        loaded.state.find_army(final_ordinary_army) == nullptr ||
        !loaded.state.orders().empty()) {
        std::cerr << "Mutual neutral combat did not consume guard and final normal slot\n";
        return false;
    }

    const CommandResult rebuild_turn = processor.execute(
        loaded.state, AdvanceTurnCommand{1}
    );
    const ArmyId deterministic_guard{"neutral_guard_cell_5_4"};
    const Army* rebuilt = loaded.state.find_army(deterministic_guard);
    if (!rebuild_turn.accepted || rebuilt == nullptr || rebuilt->owner_id != neutral ||
        rebuilt->province_id != target || rebuilt->manpower != 1 ||
        loaded.state.find_army(final_ordinary_army) == nullptr ||
        !loaded.state.validate().empty()) {
        std::cerr << "Exhausted normal allocator blocked next-month neutral rebuild\n";
        return false;
    }

    const auto round_trip_path = std::filesystem::temp_directory_path() /
        "province-schema7-neutral-combat-rebuild-round-trip.json";
    SaveGameSerializer::save(
        round_trip_path,
        loaded.state,
        processor.next_event_sequence(),
        human,
        std::nullopt
    );
    LoadedGame round_trip = SaveGameSerializer::load(round_trip_path);
    std::filesystem::remove(round_trip_path);
    bool retained_legacy_numeric_guard = false;
    for (const auto& [army_id, army] : round_trip.state.armies()) {
        if (army.owner_id == neutral && army_id.value().starts_with("army_")) {
            retained_legacy_numeric_guard = true;
            break;
        }
    }
    if (round_trip.state.find_army(deterministic_guard) == nullptr ||
        !retained_legacy_numeric_guard || !round_trip.state.validate().empty()) {
        std::cerr << "Old numeric and deterministic neutral guards did not coexist on load\n";
        return false;
    }
    return true;
}

bool test_schema7_requires_exact_historical_movement_cost_combinations() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const CountryId country_id{"auroria"};
    const auto chain = find_owned_chain(state, country_id);
    if (!chain.has_value()) {
        std::cerr << "No three-province owned chain for movement persistence test\n";
        return false;
    }
    const ProvinceId origin = (*chain)[0];
    const ProvinceId middle = (*chain)[1];
    const ProvinceId destination = (*chain)[2];
    state.find_province(middle)->terrain = TerrainType::plains;
    state.find_province(destination)->terrain = TerrainType::mountains;
    state.set_road_level(origin, middle, RoadLevel::paved);
    const ArmyId army_id = state.create_army(country_id, origin, 2'000);
    state.find_army(army_id)->movement_points =
        MovementSystem::maximum_movement_points_half(0);
    OrderSystem orders;
    const OrderOperationResult action = orders.queue_army_action(
        state, army_id, {origin, middle, destination}, false
    );
    if (!action.accepted) return false;
    const ArmyActionOrder& stored = std::get<ArmyActionOrder>(
        state.orders().at(*action.order_id)
    );
    if (stored.reserved_movement_half != 10) return false;

    state.set_road_level(middle, destination, RoadLevel::paved);
    if (!state.validate().empty()) {
        std::cerr << "Legitimate pre-road movement reservation failed validation\n";
        return false;
    }
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-historical-movement-cost.json";
    SaveGameSerializer::save(path, state, 91, country_id, std::nullopt);
    std::ifstream stream{path};
    Json document = Json::parse(stream);
    stream.close();
    std::filesystem::remove(path);
    document["orders"][order_index(document, "army_action")]
        ["reserved_movement_half"] = 8;
    if (!rejected(document, "unreachable-movement-cost-combination")) {
        std::cerr << "Schema 7 accepted an unreachable per-edge movement cost combination\n";
        return false;
    }
    return true;
}

bool test_schema7_round_trips_dynamic_invalidations_for_exact_refunds() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const CountryId country_id{"auroria"};
    const CountryId occupier_id{"caelus"};
    CountryTechnology* technology = state.find_technology(country_id);
    technology->roads_level = CountryTechnology::roads_maximum_level;
    const auto connection = find_owned_connection(state, country_id);
    if (!connection.has_value()) return false;
    const ProvinceId origin = connection->first;
    const ProvinceId destination = connection->second;
    technology->roads_level = RoadSystem::required_roads_level(
        state.find_province(origin)->terrain,
        state.find_province(destination)->terrain
    );
    const ArmyId army_id = state.create_army(country_id, origin, 2'000);
    Army* army = state.find_army(army_id);
    army->movement_points = MovementSystem::maximum_movement_points_half(
        technology->military_level
    );

    OrderSystem orders;
    const OrderOperationResult research = orders.queue_research(
        state, country_id, TechnologyTrack::economy
    );
    if (!research.accepted) return false;
    const MonthlyOrderProjectReport research_progress =
        MonthlyOrderSystem{}.resolve_projects(state);
    if (!research_progress.research.empty()) return false;
    const OrderOperationResult movement = orders.queue_army_action(
        state, army_id, {origin, destination}, false
    );
    const OrderOperationResult recruitment = orders.queue_recruitment(
        state, country_id, destination, 100
    );
    const OrderOperationResult road = orders.queue_road_construction(
        state, country_id, origin, destination
    );
    if (!movement.accepted || !recruitment.accepted || !road.accepted) return false;
    const auto* movement_order = std::get_if<ArmyActionOrder>(
        &state.orders().at(*movement.order_id)
    );
    const auto* recruitment_order = std::get_if<RecruitmentOrder>(
        &state.orders().at(*recruitment.order_id)
    );
    const auto* road_order = std::get_if<RoadConstructionOrder>(
        &state.orders().at(*road.order_id)
    );
    const auto* research_order = std::get_if<ResearchOrder>(
        &state.orders().at(*research.order_id)
    );
    if (movement_order == nullptr || recruitment_order == nullptr || road_order == nullptr ||
        research_order == nullptr || research_order->remaining_months != 1) {
        return false;
    }
    const std::int32_t movement_refund = movement_order->reserved_movement_half;
    const std::int64_t treasury_refund = recruitment_order->paid_cost +
        road_order->paid_cost + research_order->paid_cost;
    const std::int32_t movement_before_refund = state.find_army(army_id)->movement_points;
    const std::int64_t treasury_before_refund = state.find_country(country_id)->treasury;

    state.set_occupation(destination, occupier_id);
    state.set_road_level(origin, destination, RoadLevel::paved);
    technology->roads_level = CountryTechnology::roads_maximum_level;
    technology->economy_level = research_order->target_level;
    if (!state.validate().empty()) {
        std::cerr << "Dynamic execution invalidations made the order state unsaveable\n";
        return false;
    }

    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-dynamic-invalidations.json";
    SaveGameSerializer::save(path, state, 77, country_id, std::nullopt);
    LoadedGame loaded{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        loaded = SaveGameSerializer::load(path);
    } catch (const SaveGameError& error) {
        std::cerr << "Dynamic invalidation load failed: " << error.what() << "\n";
        std::filesystem::remove(path);
        return false;
    }
    std::filesystem::remove(path);

    const MonthlyOrderMovementReport movement_report =
        MonthlyOrderSystem{}.resolve_movement(loaded.state);
    const MonthlyOrderProjectReport project_report =
        MonthlyOrderSystem{}.resolve_projects(loaded.state);
    if (movement_report.refunds.size() != 1 || project_report.refunds.size() != 3 ||
        !loaded.state.orders().empty() ||
        loaded.state.find_army(army_id)->movement_points !=
            movement_before_refund + movement_refund ||
        loaded.state.find_country(country_id)->treasury !=
            treasury_before_refund + treasury_refund) {
        std::cerr << "Loaded dynamically invalid orders did not refund exactly once\n";
        return false;
    }
    return true;
}

bool test_schema7_round_trips_legal_defensive_debt() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1200, 6},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const ArmyId debt_army = state.armies().begin()->first;
    state.find_army(debt_army)->movement_points = -MovementSystem::movement_point_scale;
    const CountryId debt_country{"auroria"};
    state.find_country(debt_country)->treasury = -1'234;
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-defensive-debt.json";
    SaveGameSerializer::save(path, state, 8, debt_country, std::nullopt);
    LoadedGame loaded{
        GameState{GameClock{1, 1}}, 1, CountryId{"auroria"}, std::nullopt
    };
    try {
        loaded = SaveGameSerializer::load(path);
    } catch (const SaveGameError& error) {
        std::cerr << "Defensive debt save/load failed: " << error.what() << "\n";
        std::filesystem::remove(path);
        return false;
    }
    std::filesystem::remove(path);
    const Army* loaded_debt_army = loaded.state.find_army(debt_army);
    if (loaded_debt_army == nullptr ||
        loaded_debt_army->movement_points != -MovementSystem::movement_point_scale ||
        loaded.state.find_country(debt_country) == nullptr ||
        loaded.state.find_country(debt_country)->treasury != -1'234) {
        std::cerr << "Legal treasury or defensive movement debt did not round trip\n";
        return false;
    }

    const auto valid_path = std::filesystem::temp_directory_path() /
        "province-schema7-valid-for-debt-mutation.json";
    SaveGameSerializer::save(valid_path, state, 9, debt_country, std::nullopt);
    std::ifstream stream{valid_path};
    Json document = Json::parse(stream);
    stream.close();
    std::filesystem::remove(valid_path);
    document["armies"][0]["movement_points_half"] =
        -MovementSystem::movement_point_scale - 1;
    if (!rejected(document, "below-defensive-debt")) {
        std::cerr << "Schema 7 accepted movement below defensive debt\n";
        return false;
    }
    return true;
}

bool test_schema7_separates_player_identity_from_ai_configuration() {
    GameState state = ScenarioLoader::load(
        "game/data", GameClock{1337, 9},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    const CountryId player{"caelus"};
    const auto path = std::filesystem::temp_directory_path() /
        "province-schema7-player-identity.json";
    SaveGameSerializer::save(path, state, 73, player, std::nullopt);

    std::ifstream stream{path};
    Json document = Json::parse(stream);
    stream.close();
    LoadedGame loaded = SaveGameSerializer::load(path);
    std::filesystem::remove(path);
    if (document.at("player_country_id") != player.value() ||
        !document.at("ai_human_country_id").is_null() ||
        loaded.player_country_id != player || loaded.ai_human_country_id.has_value()) {
        std::cerr << "Schema 7 derived the player identity from optional AI configuration\n";
        return false;
    }

    Json missing_player = document;
    missing_player.erase("player_country_id");
    Json unknown_player = document;
    unknown_player["player_country_id"] = "missing_country";
    Json hidden_player = document;
    hidden_player["player_country_id"] = "neutral";
    Json mismatched_ai = document;
    mismatched_ai["ai_human_country_id"] = "auroria";
    if (!rejected(missing_player, "missing-player-country") ||
        !rejected(unknown_player, "unknown-player-country") ||
        !rejected(hidden_player, "hidden-player-country") ||
        !rejected(mismatched_ai, "mismatched-ai-human-country")) {
        std::cerr << "Schema 7 accepted malformed player/AI identity configuration\n";
        return false;
    }
    return true;
}

} // namespace

bool run_save_game_smoke_tests() {
    return test_schema7_round_trip_restores_every_order_without_recharging() &&
        test_schema7_rejects_old_versions_and_malformed_orders() &&
        test_neutral_guard_rebuild_survives_exhaustion_after_mutual_combat() &&
        test_schema7_requires_exact_historical_movement_cost_combinations() &&
        test_schema7_round_trips_dynamic_invalidations_for_exact_refunds() &&
        test_schema7_round_trips_legal_defensive_debt() &&
        test_schema7_separates_player_identity_from_ai_configuration();
}
