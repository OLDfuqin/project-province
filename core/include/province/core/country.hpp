#pragma once

#include "province/core/stable_id.hpp"

#include <cstdint>
#include <string>

namespace province::core {

struct Country final {
    CountryId id;
    std::string name;
    std::uint32_t color_rgb{};
    std::int64_t treasury{};
    std::string code;
};

} // namespace province::core
