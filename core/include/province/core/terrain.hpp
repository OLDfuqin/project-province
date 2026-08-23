#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
namespace province::core {
enum class TerrainType : std::uint8_t { plains, forest, hills, mountains, capital };
inline TerrainType terrain_from_string(const std::string& value) {
    if (value == "plains") return TerrainType::plains;
    if (value == "forest") return TerrainType::forest;
    if (value == "hills") return TerrainType::hills;
    if (value == "mountains") return TerrainType::mountains;
    if (value == "capital") return TerrainType::capital;
    throw std::invalid_argument{"unknown terrain type: " + value};
}
inline const char* terrain_name(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::plains: return "plains";
    case TerrainType::forest: return "forest";
    case TerrainType::hills: return "hills";
    case TerrainType::mountains: return "mountains";
    case TerrainType::capital: return "capital";
    }
    return "plains";
}
inline std::int32_t terrain_movement_cost(TerrainType value) noexcept {
    return value == TerrainType::mountains ? 4 :
        (value == TerrainType::plains || value == TerrainType::capital) ? 2 : 3;
}
inline std::int32_t terrain_defense_bonus(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::forest: return 10;
    case TerrainType::hills: return 20;
    case TerrainType::mountains: return 30;
    case TerrainType::capital: return 50;
    default: return 0;
    }
}
inline constexpr std::int32_t terrain_economy_percent(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::plains:
    case TerrainType::capital: return 100;
    case TerrainType::forest:
    case TerrainType::hills: return 90;
    case TerrainType::mountains: return 80;
    }
    return 100;
}
inline constexpr std::int64_t terrain_road_endpoint_cost(TerrainType value) noexcept {
    switch (terrain_economy_percent(value)) {
    case 100: return 300;
    case 90: return 500;
    default: return 700;
    }
}
} // namespace province::core
