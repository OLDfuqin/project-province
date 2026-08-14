#include "province/core/scenario_loader.hpp"

#include "province/core/country.hpp"
#include "province/core/province.hpp"
#include "province/core/stable_id.hpp"

#include <nlohmann/json.hpp>

#include <charconv>
#include <cstdint>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace province::core {
namespace {

constexpr std::int32_t supported_schema_version = 4;

using Json = nlohmann::json;

[[nodiscard]] Json read_document(const std::filesystem::path& path) {
    std::ifstream stream{path};
    if (!stream) {
        throw DataLoadError{"cannot open data file: " + path.string()};
    }

    try {
        return Json::parse(stream);
    } catch (const Json::exception& error) {
        throw DataLoadError{
            "invalid JSON in '" + path.string() + "': " + error.what()
        };
    }
}

void require_schema_version(const Json& document, const std::filesystem::path& path) {
    try {
        const auto version = document.at("schema_version").get<std::int32_t>();
        if (version != supported_schema_version) {
            throw DataLoadError{
                "unsupported schema version " + std::to_string(version) + " in '" +
                path.string() + "'; expected " +
                std::to_string(supported_schema_version)
            };
        }
    } catch (const Json::exception& error) {
        throw DataLoadError{
            "invalid schema_version in '" + path.string() + "': " + error.what()
        };
    }
}

[[nodiscard]] std::uint32_t parse_color(const std::string_view color) {
    if (color.size() != 7 || color.front() != '#') {
        throw std::invalid_argument{"country color must use #RRGGBB format"};
    }

    std::uint32_t value{};
    const auto result = std::from_chars(color.data() + 1, color.data() + color.size(), value, 16);
    if (result.ec != std::errc{} || result.ptr != color.data() + color.size()) {
        throw std::invalid_argument{"country color contains invalid hexadecimal digits"};
    }
    return value;
}

void load_countries(GameState& state, const std::filesystem::path& path) {
    const Json document = read_document(path);
    require_schema_version(document, path);

    try {
        for (const Json& entry : document.at("countries")) {
            state.add_country(Country{
                CountryId{entry.at("id").get<std::string>()},
                entry.at("name").get<std::string>(),
                parse_color(entry.at("color").get<std::string>()),
                entry.at("treasury").get<std::int64_t>(),
                entry.at("code").get<std::string>(),
            });
        }
    } catch (const DataLoadError&) {
        throw;
    } catch (const std::exception& error) {
        throw DataLoadError{
            "invalid country data in '" + path.string() + "': " + error.what()
        };
    }
}

void load_provinces(GameState& state, const std::filesystem::path& path) {
    const Json document = read_document(path);
    require_schema_version(document, path);

    try {
        for (const Json& entry : document.at("provinces")) {
            std::vector<ProvinceId> neighbors;
            for (const Json& neighbor : entry.at("neighbors")) {
                neighbors.emplace_back(neighbor.get<std::string>());
            }

            Province province{
                ProvinceId{entry.at("id").get<std::string>()},
                entry.at("name").get<std::string>(),
                CountryId{entry.at("owner_id").get<std::string>()},
                entry.at("population").get<std::int64_t>(),
                entry.at("recruitable_population").get<std::int64_t>(),
                std::move(neighbors),
            };
            province.terrain = terrain_from_string(entry.value("terrain", "plains"));
            state.add_province(std::move(province));
        }
    } catch (const DataLoadError&) {
        throw;
    } catch (const std::exception& error) {
        throw DataLoadError{
            "invalid province data in '" + path.string() + "': " + error.what()
        };
    }
}

[[nodiscard]] std::string join_issues(const std::vector<std::string>& issues) {
    std::ostringstream message;
    message << "scenario validation failed:";
    for (const std::string& issue : issues) {
        message << "\n- " << issue;
    }
    return message.str();
}

} // namespace

DataLoadError::DataLoadError(const std::string& message) : std::runtime_error{message} {}

GameState ScenarioLoader::load(
    const std::filesystem::path& data_directory,
    GameClock initial_clock
) {
    GameState state{std::move(initial_clock)};
    load_countries(state, data_directory / "countries.json");
    load_provinces(state, data_directory / "provinces.json");

    const std::vector<std::string> issues = state.validate();
    if (!issues.empty()) {
        throw DataLoadError{join_issues(issues)};
    }
    return state;
}

} // namespace province::core
