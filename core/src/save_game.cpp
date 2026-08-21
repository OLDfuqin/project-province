#include "province/core/save_game.hpp"

#include <nlohmann/json.hpp>

#include <fstream>
#include <limits>
#include <optional>
#include <sstream>
#include <string>
#include <utility>

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

std::string join_issues(const std::vector<std::string>& issues) {
    std::ostringstream message;
    message << "save validation failed:";
    for (const std::string& issue : issues) {
        message << "\n- " << issue;
    }
    return message.str();
}

std::string legacy_country_code(const CountryId& country_id) {
    if (country_id == CountryId{"auroria"}) {
        return "\xE5\xA5\xA5";
    }
    if (country_id == CountryId{"verdantia"}) {
        return "\xE7\xBB\xB4";
    }
    if (country_id == CountryId{"caelus"}) {
        return "\xE5\x87\xAF";
    }
    if (country_id == CountryId{"solmere"}) {
        return "\xE7\xB4\xA2";
    }
    throw SaveGameError{
        "schema 3 save contains a country without a known code: " +
        country_id.value()
    };
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
    Json document{
        {"schema_version", schema_version},
        {"clock", {{"year", state.clock().year()}, {"month", state.clock().month()}}},
        {"next_event_sequence", next_event_sequence},
        {"human_country_id", human_country_id.has_value()
            ? Json(human_country_id->value())
            : Json(nullptr)},
        {"next_army_sequence", state.next_army_sequence_},
        {"countries", Json::array()},
        {"provinces", Json::array()},
        {"roads", Json::array()},
        {"armies", Json::array()},
        {"occupations", Json::array()},
        {"relations", Json::array()},
        {"technologies", Json::array()},
    };

    for (const auto& [country_id, country] : state.countries_) {
        document["countries"].push_back({
            {"id", country_id.value()},
            {"name", country.name},
            {"code", country.code},
            {"color_rgb", country.color_rgb},
            {"treasury", country.treasury},
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
        const std::int32_t version = document.at("schema_version").get<std::int32_t>();
        if (version != 3 && version != 4 && version != schema_version) {
            throw SaveGameError{
                "unsupported save schema version " + std::to_string(version) +
                "; expected 3, 4 or " + std::to_string(schema_version)
            };
        }
        const Json& clock = document.at("clock");
        GameState state{GameClock{
            clock.at("year").get<std::int32_t>(),
            clock.at("month").get<std::int32_t>(),
        }};
        for (const Json& entry : document.at("countries")) {
            const CountryId country_id{entry.at("id").get<std::string>()};
            state.add_country(Country{
                country_id,
                entry.at("name").get<std::string>(),
                entry.at("color_rgb").get<std::uint32_t>(),
                entry.at("treasury").get<std::int64_t>(),
                version == 3
                    ? legacy_country_code(country_id)
                    : entry.at("code").get<std::string>(),
            });
        }
        for (const Json& entry : document.at("provinces")) {
            std::vector<ProvinceId> neighbors;
            for (const Json& neighbor : entry.at("neighbors")) {
                neighbors.emplace_back(neighbor.get<std::string>());
            }
            state.add_province(Province{
                ProvinceId{entry.at("id").get<std::string>()},
                entry.at("name").get<std::string>(),
                CountryId{entry.at("owner_id").get<std::string>()},
                entry.at("population").get<std::int64_t>(),
                entry.at("recruitable_population").get<std::int64_t>(),
                std::move(neighbors),
                entry.at("population_growth_remainder").get<std::int64_t>(),
                terrain_from_string(entry.value("terrain", "plains")),
            });
        }
        for (const Json& entry : document.at("roads")) {
            state.set_road_level(
                ProvinceId{entry.at("province_a").get<std::string>()},
                ProvinceId{entry.at("province_b").get<std::string>()},
                parse_road_level(entry.at("level").get<std::string>())
            );
        }
        for (const Json& entry : document.at("armies")) {
            const ArmyId id{entry.at("id").get<std::string>()};
            const CountryId owner_id{entry.at("owner_id").get<std::string>()};
            std::optional<ProvinceId> advance_target;
            if (entry.contains("advance_target")) {
                advance_target.emplace(entry.at("advance_target").get<std::string>());
            }
            const std::int64_t movement_points_half = version == schema_version
                ? entry.at("movement_points_half").get<std::int64_t>()
                : entry.at("movement_points").get<std::int64_t>() * 2;
            if (movement_points_half < 0 || movement_points_half >
                std::numeric_limits<std::int32_t>::max()) {
                throw SaveGameError{"army movement points are out of range"};
            }
            const auto [iterator, inserted] = state.armies_.emplace(
                id,
                Army{
                    id,
                    owner_id,
                    ProvinceId{entry.at("province_id").get<std::string>()},
                    entry.at("manpower").get<std::int64_t>(),
                    static_cast<std::int32_t>(movement_points_half),
                    std::move(advance_target),
                    entry.value("advance_enabled", true),
                    entry.value("advance_strategy", std::string{"max"}),
                    version == 3
                        ? state.next_formation_number(owner_id)
                        : entry.at("formation_number").get<std::int64_t>(),
                }
            );
            static_cast<void>(iterator);
            if (!inserted) {
                throw SaveGameError{"duplicate army ID in save: " + id.value()};
            }
        }
        for (const Json& entry : document.at("occupations")) {
            state.set_occupation(
                ProvinceId{entry.at("province_id").get<std::string>()},
                CountryId{entry.at("controller_id").get<std::string>()}
            );
        }
        for (const Json& entry : document.at("relations")) {
            state.set_diplomatic_status(
                CountryId{entry.at("country_a").get<std::string>()},
                CountryId{entry.at("country_b").get<std::string>()},
                parse_diplomatic_status(entry.at("status").get<std::string>())
            );
        }
        for (const Json& entry : document.at("technologies")) {
            CountryTechnology* technology = state.find_technology(
                CountryId{entry.at("country_id").get<std::string>()}
            );
            if (technology == nullptr) {
                throw SaveGameError{"technology references an unknown country"};
            }
            technology->economy_level = entry.at("economy_level").get<std::int32_t>();
            technology->military_level = entry.at("military_level").get<std::int32_t>();
            technology->roads_level = entry.at("roads_level").get<std::int32_t>();
        }
        state.next_army_sequence_ = document.at("next_army_sequence").get<std::uint64_t>();
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
        const std::uint64_t next_event_sequence =
            document.at("next_event_sequence").get<std::uint64_t>();
        if (next_event_sequence == 0 || state.next_army_sequence_ == 0) {
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
