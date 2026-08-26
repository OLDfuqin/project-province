#include "province/core/save_game.hpp"
#include "province/core/army_system.hpp"
#include "province/core/movement_system.hpp"
#include "province/core/road_system.hpp"
#include "province/core/technology_system.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <fstream>
#include <initializer_list>
#include <limits>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>

namespace province::core {
namespace {

using Json = nlohmann::json;

std::string road_level_name(const RoadLevel level) {
    return level == RoadLevel::paved ? "paved" : "none";
}

RoadLevel parse_road_level(const std::string& value) {
    if (value == "paved") {
        return RoadLevel::paved;
    }
    if (value == "none") {
        return RoadLevel::none;
    }
    throw SaveGameError{"unknown road level: " + value};
}

std::string diplomatic_status_name(const DiplomaticStatus status) {
    return status == DiplomaticStatus::war ? "war" : "peace";
}

DiplomaticStatus parse_diplomatic_status(const std::string& value) {
    if (value == "war") {
        return DiplomaticStatus::war;
    }
    if (value == "peace") {
        return DiplomaticStatus::peace;
    }
    throw SaveGameError{"unknown diplomatic status: " + value};
}

std::string technology_track_name(const TechnologyTrack track) {
    switch (track) {
    case TechnologyTrack::economy: return "economy";
    case TechnologyTrack::military: return "military";
    case TechnologyTrack::roads: return "roads";
    }
    throw SaveGameError{"unknown technology track"};
}

TechnologyTrack parse_technology_track(const std::string& value) {
    if (value == "economy") return TechnologyTrack::economy;
    if (value == "military") return TechnologyTrack::military;
    if (value == "roads") return TechnologyTrack::roads;
    throw SaveGameError{"unknown technology track: " + value};
}

void require_object_fields(
    const Json& object,
    const std::initializer_list<const char*> required,
    const std::initializer_list<const char*> optional = {}
) {
    if (!object.is_object()) {
        throw SaveGameError{"save entry must be a JSON object"};
    }
    std::set<std::string> allowed;
    for (const char* field : required) {
        allowed.emplace(field);
        if (!object.contains(field)) {
            throw SaveGameError{"save entry is missing required field: " + std::string{field}};
        }
    }
    for (const char* field : optional) allowed.emplace(field);
    for (const auto& [field, value] : object.items()) {
        static_cast<void>(value);
        if (!allowed.contains(field)) {
            throw SaveGameError{"save entry contains unknown field: " + field};
        }
    }
}

void require_array(const Json& value, const std::string& field) {
    if (!value.is_array()) {
        throw SaveGameError{"save field must be an array: " + field};
    }
}

template <typename Integer>
Integer integral_value(const Json& value, const std::string& field) {
    static_assert(std::is_integral_v<Integer> && !std::is_same_v<Integer, bool>);
    if (value.is_number_unsigned()) {
        const std::uint64_t raw = value.get<std::uint64_t>();
        if (raw > static_cast<std::uint64_t>(std::numeric_limits<Integer>::max())) {
            throw SaveGameError{"save integer is out of range: " + field};
        }
        return static_cast<Integer>(raw);
    }
    if (value.is_number_integer()) {
        const std::int64_t raw = value.get<std::int64_t>();
        if constexpr (std::is_unsigned_v<Integer>) {
            if (raw < 0 || static_cast<std::uint64_t>(raw) >
                    std::numeric_limits<Integer>::max()) {
                throw SaveGameError{"save integer is out of range: " + field};
            }
        } else if (raw < static_cast<std::int64_t>(std::numeric_limits<Integer>::min()) ||
                   raw > static_cast<std::int64_t>(std::numeric_limits<Integer>::max())) {
            throw SaveGameError{"save integer is out of range: " + field};
        }
        return static_cast<Integer>(raw);
    }
    throw SaveGameError{"save field must be an integer: " + field};
}

Json serialize_order(const GameOrder& order) {
    return std::visit([](const auto& typed_order) -> Json {
        using OrderType = std::decay_t<decltype(typed_order)>;
        if constexpr (std::is_same_v<OrderType, ArmyActionOrder>) {
            Json path = Json::array();
            for (const ProvinceId& province_id : typed_order.path) {
                path.push_back(province_id.value());
            }
            return {
                {"type", "army_action"},
                {"id", typed_order.id.value()},
                {"army_id", typed_order.army_id.value()},
                {"country_id", typed_order.country_id.value()},
                {"origin", typed_order.origin.value()},
                {"destination", typed_order.destination.value()},
                {"path", std::move(path)},
                {"reserved_movement_half", typed_order.reserved_movement_half},
                {"is_attack", typed_order.is_attack},
            };
        } else if constexpr (std::is_same_v<OrderType, RecruitmentOrder>) {
            return {
                {"type", "recruitment"},
                {"id", typed_order.id.value()},
                {"country_id", typed_order.country_id.value()},
                {"province_id", typed_order.province_id.value()},
                {"manpower", typed_order.manpower},
                {"paid_cost", typed_order.paid_cost},
                {"remaining_months", typed_order.remaining_months},
            };
        } else if constexpr (std::is_same_v<OrderType, RoadConstructionOrder>) {
            return {
                {"type", "road_construction"},
                {"id", typed_order.id.value()},
                {"country_id", typed_order.country_id.value()},
                {"province_a", typed_order.province_a.value()},
                {"province_b", typed_order.province_b.value()},
                {"paid_cost", typed_order.paid_cost},
                {"remaining_months", typed_order.remaining_months},
            };
        } else if constexpr (std::is_same_v<OrderType, ResearchOrder>) {
            return {
                {"type", "research"},
                {"id", typed_order.id.value()},
                {"country_id", typed_order.country_id.value()},
                {"track", technology_track_name(typed_order.track)},
                {"previous_level", typed_order.previous_level},
                {"target_level", typed_order.target_level},
                {"paid_cost", typed_order.paid_cost},
                {"remaining_months", typed_order.remaining_months},
            };
        } else {
            return {
                {"type", "war_declaration"},
                {"id", typed_order.id.value()},
                {"country_id", typed_order.country_id.value()},
                {"defender_id", typed_order.defender_id.value()},
            };
        }
    }, order);
}

GameOrder parse_order(const Json& entry) {
    if (!entry.is_object() || !entry.contains("type") ||
        !entry.at("type").is_string()) {
        throw SaveGameError{"order entry requires a string type"};
    }
    const std::string type = entry.at("type").get<std::string>();
    if (type == "army_action") {
        require_object_fields(entry, {
            "type", "id", "army_id", "country_id", "origin", "destination",
            "path", "reserved_movement_half", "is_attack",
        });
        require_array(entry.at("path"), "order.path");
        std::vector<ProvinceId> path;
        path.reserve(entry.at("path").size());
        for (const Json& province : entry.at("path")) {
            path.emplace_back(province.get<std::string>());
        }
        return ArmyActionOrder{
            OrderId{entry.at("id").get<std::string>()},
            ArmyId{entry.at("army_id").get<std::string>()},
            CountryId{entry.at("country_id").get<std::string>()},
            ProvinceId{entry.at("origin").get<std::string>()},
            ProvinceId{entry.at("destination").get<std::string>()},
            std::move(path),
            integral_value<std::int32_t>(
                entry.at("reserved_movement_half"), "order.reserved_movement_half"
            ),
            entry.at("is_attack").get<bool>(),
        };
    }
    if (type == "recruitment") {
        require_object_fields(entry, {
            "type", "id", "country_id", "province_id", "manpower", "paid_cost",
            "remaining_months",
        });
        return RecruitmentOrder{
            OrderId{entry.at("id").get<std::string>()},
            CountryId{entry.at("country_id").get<std::string>()},
            ProvinceId{entry.at("province_id").get<std::string>()},
            integral_value<std::int64_t>(entry.at("manpower"), "order.manpower"),
            integral_value<std::int64_t>(entry.at("paid_cost"), "order.paid_cost"),
            integral_value<std::int32_t>(
                entry.at("remaining_months"), "order.remaining_months"
            ),
        };
    }
    if (type == "road_construction") {
        require_object_fields(entry, {
            "type", "id", "country_id", "province_a", "province_b", "paid_cost",
            "remaining_months",
        });
        return RoadConstructionOrder{
            OrderId{entry.at("id").get<std::string>()},
            CountryId{entry.at("country_id").get<std::string>()},
            ProvinceId{entry.at("province_a").get<std::string>()},
            ProvinceId{entry.at("province_b").get<std::string>()},
            integral_value<std::int64_t>(entry.at("paid_cost"), "order.paid_cost"),
            integral_value<std::int32_t>(
                entry.at("remaining_months"), "order.remaining_months"
            ),
        };
    }
    if (type == "research") {
        require_object_fields(entry, {
            "type", "id", "country_id", "track", "previous_level", "target_level",
            "paid_cost", "remaining_months",
        });
        return ResearchOrder{
            OrderId{entry.at("id").get<std::string>()},
            CountryId{entry.at("country_id").get<std::string>()},
            parse_technology_track(entry.at("track").get<std::string>()),
            integral_value<std::int32_t>(
                entry.at("previous_level"), "order.previous_level"
            ),
            integral_value<std::int32_t>(entry.at("target_level"), "order.target_level"),
            integral_value<std::int64_t>(entry.at("paid_cost"), "order.paid_cost"),
            integral_value<std::int32_t>(
                entry.at("remaining_months"), "order.remaining_months"
            ),
        };
    }
    if (type == "war_declaration") {
        require_object_fields(entry, {"type", "id", "country_id", "defender_id"});
        return WarDeclarationOrder{
            OrderId{entry.at("id").get<std::string>()},
            CountryId{entry.at("country_id").get<std::string>()},
            CountryId{entry.at("defender_id").get<std::string>()},
        };
    }
    throw SaveGameError{"unknown order type: " + type};
}

std::string join_issues(const std::vector<std::string>& issues) {
    std::ostringstream message;
    message << "save validation failed:";
    for (const std::string& issue : issues) {
        message << "\n- " << issue;
    }
    return message.str();
}

} // namespace

SaveGameError::SaveGameError(const std::string& message) : std::runtime_error{message} {}

void SaveGameSerializer::save(
    const std::filesystem::path& path,
    const GameState& state,
    const std::uint64_t next_event_sequence,
    const std::optional<CountryId>& human_country_id
) {
    const std::vector<std::string> issues = state.validate();
    if (!issues.empty()) {
        throw SaveGameError{join_issues(issues)};
    }
    if (state.map_layout_id() != "generated_grid_v1") {
        throw SaveGameError{"only generated_grid_v1 states can be saved"};
    }
    Json document{
        {"schema_version", schema_version},
        {"map_layout_id", state.map_layout_id()},
        {"clock", {{"year", state.clock().year()}, {"month", state.clock().month()}}},
        {"next_event_sequence", next_event_sequence},
        {"human_country_id", human_country_id.has_value()
            ? Json(human_country_id->value())
            : Json(nullptr)},
        {"next_army_sequence", state.next_army_sequence_},
        {"next_order_sequence", state.next_order_sequence_},
        {"countries", Json::array()},
        {"provinces", Json::array()},
        {"roads", Json::array()},
        {"armies", Json::array()},
        {"occupations", Json::array()},
        {"relations", Json::array()},
        {"technologies", Json::array()},
        {"orders", Json::array()},
    };

    for (const auto& [country_id, country] : state.countries_) {
        document["countries"].push_back({
            {"id", country_id.value()},
            {"name", country.name},
            {"code", country.code},
            {"color_rgb", country.color_rgb},
            {"treasury", country.treasury},
            {"hidden", country.hidden},
        });
    }
    for (const auto& [province_id, province] : state.provinces_) {
        Json neighbors = Json::array();
        for (const ProvinceId& neighbor : province.neighbors) {
            neighbors.push_back(neighbor.value());
        }
        document["provinces"].push_back({
            {"id", province_id.value()},
            {"name", province.name},
            {"owner_id", province.owner_id.value()},
            {"population", province.population},
            {"recruitable_population", province.recruitable_population},
            {"base_economy", province.base_economy},
            {"neighbors", std::move(neighbors)},
            {"population_growth_remainder", province.population_growth_remainder},
            {"terrain", terrain_name(province.terrain)},
        });
    }
    for (const auto& [connection, level] : state.roads_) {
        document["roads"].push_back({
            {"province_a", connection.first().value()},
            {"province_b", connection.second().value()},
            {"level", road_level_name(level)},
        });
    }
    for (const auto& [army_id, army] : state.armies_) {
        Json army_document = {
            {"id", army_id.value()},
            {"owner_id", army.owner_id.value()},
            {"province_id", army.province_id.value()},
            {"manpower", army.manpower},
            {"movement_points_half", army.movement_points},
            {"formation_number", army.formation_number},
        };
        if (army.advance_target.has_value()) {
            army_document["advance_target"] = army.advance_target->value();
        }
        army_document["advance_enabled"] = army.advance_enabled;
        army_document["advance_strategy"] = army.advance_strategy;
        document["armies"].push_back(std::move(army_document));
    }
    for (const auto& [province_id, controller_id] : state.occupations_) {
        document["occupations"].push_back({
            {"province_id", province_id.value()},
            {"controller_id", controller_id.value()},
        });
    }
    for (const auto& [relation, status] : state.relations_) {
        document["relations"].push_back({
            {"country_a", relation.first().value()},
            {"country_b", relation.second().value()},
            {"status", diplomatic_status_name(status)},
        });
    }
    for (const auto& [country_id, technology] : state.technologies_) {
        document["technologies"].push_back({
            {"country_id", country_id.value()},
            {"economy_level", technology.economy_level},
            {"military_level", technology.military_level},
            {"roads_level", technology.roads_level},
        });
    }
    for (const auto& [id, order] : state.orders_) {
        static_cast<void>(id);
        document["orders"].push_back(serialize_order(order));
    }

    if (!path.parent_path().empty()) {
        std::filesystem::create_directories(path.parent_path());
    }
    const std::filesystem::path temporary = path.string() + ".tmp";
    {
        std::ofstream stream{temporary, std::ios::trunc};
        if (!stream) {
            throw SaveGameError{"cannot open temporary save file: " + temporary.string()};
        }
        stream << document.dump(2) << '\n';
        if (!stream) {
            throw SaveGameError{"failed writing temporary save file: " + temporary.string()};
        }
    }
    std::error_code error;
    if (std::filesystem::exists(path)) {
        std::filesystem::copy_file(
            temporary,
            path,
            std::filesystem::copy_options::overwrite_existing,
            error
        );
        if (!error) {
            std::filesystem::remove(temporary);
        }
    } else {
        std::filesystem::rename(temporary, path, error);
    }
    if (error) {
        throw SaveGameError{"cannot finalize save file: " + error.message()};
    }
}

LoadedGame SaveGameSerializer::load(const std::filesystem::path& path) {
    std::ifstream stream{path};
    if (!stream) {
        throw SaveGameError{"cannot open save file: " + path.string()};
    }
    try {
        const Json document = Json::parse(stream);
        const std::int32_t version = integral_value<std::int32_t>(
            document.at("schema_version"), "schema_version"
        );
        if (version != schema_version) {
            throw SaveGameError{
                "old 32-province save is incompatible; expected schema " +
                std::to_string(schema_version)
            };
        }
        require_object_fields(document, {
            "schema_version", "map_layout_id", "clock", "next_event_sequence",
            "human_country_id", "next_army_sequence", "next_order_sequence", "countries",
            "provinces", "roads", "armies", "occupations", "relations", "technologies",
            "orders",
        });
        const std::string map_layout_id =
            document.at("map_layout_id").get<std::string>();
        if (map_layout_id != "generated_grid_v1") {
            throw SaveGameError{"save map layout is incompatible with generated_grid_v1"};
        }
        const Json& clock = document.at("clock");
        require_object_fields(clock, {"year", "month"});
        GameState state{GameClock{
            integral_value<std::int32_t>(clock.at("year"), "clock.year"),
            integral_value<std::int32_t>(clock.at("month"), "clock.month"),
        }};
        state.map_layout_id_ = map_layout_id;
        require_array(document.at("countries"), "countries");
        for (const Json& entry : document.at("countries")) {
            require_object_fields(entry, {
                "id", "name", "code", "color_rgb", "treasury", "hidden",
            });
            const CountryId country_id{entry.at("id").get<std::string>()};
            const std::int64_t treasury = integral_value<std::int64_t>(
                entry.at("treasury"), "country.treasury"
            );
            state.add_country(Country{
                country_id,
                entry.at("name").get<std::string>(),
                integral_value<std::uint32_t>(entry.at("color_rgb"), "country.color_rgb"),
                std::max<std::int64_t>(0, treasury),
                entry.at("code").get<std::string>(),
                entry.at("hidden").get<bool>(),
            });
            state.find_country(country_id)->treasury = treasury;
        }
        require_array(document.at("provinces"), "provinces");
        for (const Json& entry : document.at("provinces")) {
            require_object_fields(entry, {
                "id", "name", "owner_id", "population", "recruitable_population",
                "base_economy", "neighbors", "population_growth_remainder", "terrain",
            });
            require_array(entry.at("neighbors"), "province.neighbors");
            std::vector<ProvinceId> neighbors;
            for (const Json& neighbor : entry.at("neighbors")) {
                neighbors.emplace_back(neighbor.get<std::string>());
            }
            const std::int64_t population = integral_value<std::int64_t>(
                entry.at("population"), "province.population"
            );
            const TerrainType terrain = terrain_from_string(
                entry.at("terrain").get<std::string>()
            );
            const std::int64_t base_economy =
                integral_value<std::int64_t>(
                    entry.at("base_economy"), "province.base_economy"
                );
            state.add_province(Province{
                ProvinceId{entry.at("id").get<std::string>()},
                entry.at("name").get<std::string>(),
                CountryId{entry.at("owner_id").get<std::string>()},
                population,
                integral_value<std::int64_t>(
                    entry.at("recruitable_population"), "province.recruitable_population"
                ),
                base_economy,
                std::move(neighbors),
                integral_value<std::int64_t>(
                    entry.at("population_growth_remainder"),
                    "province.population_growth_remainder"
                ),
                terrain,
            });
        }
        require_array(document.at("roads"), "roads");
        std::set<ProvinceConnectionKey> loaded_roads;
        for (const Json& entry : document.at("roads")) {
            require_object_fields(entry, {"province_a", "province_b", "level"});
            const ProvinceId province_a{entry.at("province_a").get<std::string>()};
            const ProvinceId province_b{entry.at("province_b").get<std::string>()};
            if (!loaded_roads.emplace(province_a, province_b).second) {
                throw SaveGameError{"duplicate road connection in save"};
            }
            state.set_road_level(
                province_a,
                province_b,
                parse_road_level(entry.at("level").get<std::string>())
            );
        }
        require_array(document.at("armies"), "armies");
        for (const Json& entry : document.at("armies")) {
            require_object_fields(
                entry,
                {
                    "id", "owner_id", "province_id", "manpower", "movement_points_half",
                    "advance_enabled", "advance_strategy", "formation_number",
                },
                {"advance_target"}
            );
            const ArmyId id{entry.at("id").get<std::string>()};
            const CountryId owner_id{entry.at("owner_id").get<std::string>()};
            std::optional<ProvinceId> advance_target;
            if (entry.contains("advance_target")) {
                advance_target.emplace(entry.at("advance_target").get<std::string>());
            }
            const std::int64_t movement_points_half =
                integral_value<std::int64_t>(
                    entry.at("movement_points_half"), "army.movement_points_half"
                );
            if (movement_points_half < -MovementSystem::movement_point_scale ||
                movement_points_half >
                std::numeric_limits<std::int32_t>::max()) {
                throw SaveGameError{"army movement points are out of range"};
            }
            const auto [iterator, inserted] = state.armies_.emplace(
                id,
                Army{
                    id,
                    owner_id,
                    ProvinceId{entry.at("province_id").get<std::string>()},
                    integral_value<std::int64_t>(entry.at("manpower"), "army.manpower"),
                    static_cast<std::int32_t>(movement_points_half),
                    std::move(advance_target),
                    entry.at("advance_enabled").get<bool>(),
                    entry.at("advance_strategy").get<std::string>(),
                    integral_value<std::int64_t>(
                        entry.at("formation_number"), "army.formation_number"
                    ),
                }
            );
            static_cast<void>(iterator);
            if (!inserted) {
                throw SaveGameError{"duplicate army ID in save: " + id.value()};
            }
        }
        require_array(document.at("occupations"), "occupations");
        std::set<ProvinceId> loaded_occupations;
        for (const Json& entry : document.at("occupations")) {
            require_object_fields(entry, {"province_id", "controller_id"});
            const ProvinceId province_id{entry.at("province_id").get<std::string>()};
            if (!loaded_occupations.insert(province_id).second) {
                throw SaveGameError{"duplicate occupation in save"};
            }
            state.set_occupation(
                province_id,
                CountryId{entry.at("controller_id").get<std::string>()}
            );
        }
        require_array(document.at("relations"), "relations");
        std::set<CountryRelationKey> loaded_relations;
        for (const Json& entry : document.at("relations")) {
            require_object_fields(entry, {"country_a", "country_b", "status"});
            const CountryId country_a{entry.at("country_a").get<std::string>()};
            const CountryId country_b{entry.at("country_b").get<std::string>()};
            if (!loaded_relations.emplace(country_a, country_b).second) {
                throw SaveGameError{"duplicate diplomatic relation in save"};
            }
            state.set_diplomatic_status(
                country_a,
                country_b,
                parse_diplomatic_status(entry.at("status").get<std::string>())
            );
        }
        require_array(document.at("technologies"), "technologies");
        std::set<CountryId> loaded_technologies;
        for (const Json& entry : document.at("technologies")) {
            require_object_fields(entry, {
                "country_id", "economy_level", "military_level", "roads_level",
            });
            const CountryId country_id{entry.at("country_id").get<std::string>()};
            if (!loaded_technologies.insert(country_id).second) {
                throw SaveGameError{"duplicate technology state in save"};
            }
            CountryTechnology* technology = state.find_technology(country_id);
            if (technology == nullptr) {
                throw SaveGameError{"technology references an unknown country"};
            }
            technology->economy_level = integral_value<std::int32_t>(
                entry.at("economy_level"), "technology.economy_level"
            );
            technology->military_level = integral_value<std::int32_t>(
                entry.at("military_level"), "technology.military_level"
            );
            technology->roads_level = integral_value<std::int32_t>(
                entry.at("roads_level"), "technology.roads_level"
            );
        }
        if (loaded_technologies.size() != state.country_count()) {
            throw SaveGameError{"save is missing one or more country technology states"};
        }
        state.next_army_sequence_ = integral_value<std::uint64_t>(
            document.at("next_army_sequence"), "next_army_sequence"
        );
        state.next_order_sequence_ = integral_value<std::uint64_t>(
            document.at("next_order_sequence"), "next_order_sequence"
        );
        require_array(document.at("orders"), "orders");
        for (const Json& entry : document.at("orders")) {
            GameOrder order = parse_order(entry);
            const OrderId id = order_id(order);
            if (!state.orders_.emplace(id, std::move(order)).second) {
                throw SaveGameError{"duplicate order ID in save: " + id.value()};
            }
        }
        const std::vector<std::string> issues = state.validate();
        if (!issues.empty()) {
            throw SaveGameError{join_issues(issues)};
        }

        std::optional<CountryId> human_country_id;
        if (!document.at("human_country_id").is_null()) {
            human_country_id.emplace(
                document.at("human_country_id").get<std::string>()
            );
            if (state.find_country(*human_country_id) == nullptr) {
                throw SaveGameError{"human country does not exist in loaded state"};
            }
        }
        const std::uint64_t next_event_sequence = integral_value<std::uint64_t>(
            document.at("next_event_sequence"), "next_event_sequence"
        );
        if (next_event_sequence == 0 || state.next_army_sequence_ == 0 ||
            state.next_order_sequence_ == 0) {
            throw SaveGameError{"saved sequence counters must be positive"};
        }
        LoadedGame loaded{
            std::move(state),
            next_event_sequence,
            std::move(human_country_id),
        };
        return loaded;
    } catch (const SaveGameError&) {
        throw;
    } catch (const std::exception& error) {
        throw SaveGameError{"invalid save file '" + path.string() + "': " + error.what()};
    }
}

} // namespace province::core
