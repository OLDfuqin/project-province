#pragma once

#include "province/core/data_load_error.hpp"
#include "province/core/stable_id.hpp"

#include <compare>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace province::core {

struct GridCoordinate final {
    std::int32_t x{};
    std::int32_t y{};
    auto operator<=>(const GridCoordinate&) const = default;
};

struct CountryGridPlacement final {
    CountryId country_id;
    GridCoordinate minimum;
    GridCoordinate maximum;
    std::vector<GridCoordinate> capital_cells;
};

struct GridMapLayout final {
    std::string layout_id;
    std::int32_t width{};
    std::int32_t height{};
    std::int32_t cell_size{};
    std::vector<CountryGridPlacement> countries;
};

class GridMapLayoutLoader final {
public:
    [[nodiscard]] static GridMapLayout load(const std::filesystem::path& path);
};

} // namespace province::core
