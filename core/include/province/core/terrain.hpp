#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
namespace province::core {
enum class TerrainType : std::uint8_t { plains, forest, hills, mountains };
inline TerrainType terrain_from_string(const std::string& value) {
    if (value == "plains") return TerrainType::plains;
    if (value == "forest") return TerrainType::forest;
    if (value == "hills") return TerrainType::hills;
    if (value == "mountains") return TerrainType::mountains;
    throw std::invalid_argument{"unknown terrain type: " + value};
}
inline const char* terrain_name(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::plains: return "plains";
    case TerrainType::forest: return "forest";
    case TerrainType::hills: return "hills";
    case TerrainType::mountains: return "mountains";
    }
    return "plains";
}
inline std::int32_t terrain_movement_cost(TerrainType value) noexcept {
    return value == TerrainType::mountains ? 4 : value == TerrainType::plains ? 2 : 3;
}
inline std::int32_t terrain_defense_bonus(TerrainType value) noexcept {
    switch (value) {
    case TerrainType::forest: return 10;
    case TerrainType::hills: return 20;
    case TerrainType::mountains: return 30;
    default: return 0;
    }
}
} // namespace province::core
