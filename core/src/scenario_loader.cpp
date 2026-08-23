#include "province/core/scenario_loader.hpp"

#include "province/core/country.hpp"
#include "province/core/grid_map_layout.hpp"
#include "province/core/map_scenario_generator.hpp"
#include "province/core/province.hpp"
#include "province/core/stable_id.hpp"

#include <nlohmann/json.hpp>

#include <charconv>
#include <cstdint>
#include <fstream>
#include <memory>
#include <random>
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
    GameClock initial_clock,
    RandomIndexSource random_index
) {
    GameState state{std::move(initial_clock)};
    load_countries(state, data_directory / "countries.json");
    const GridMapLayout layout = GridMapLayoutLoader::load(
        data_directory / "grid_map_layout.json"
    );
    if (!random_index) {
        auto engine = std::make_shared<std::mt19937_64>(std::random_device{}());
        random_index = [engine](const std::uint32_t bound) {
            if (bound == 0) throw std::invalid_argument{"random bound cannot be zero"};
            return std::uniform_int_distribution<std::uint32_t>{0, bound - 1}(*engine);
        };
    }
    return MapScenarioGenerator::generate(std::move(state), layout, random_index);
}

} // namespace province::core
