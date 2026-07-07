#pragma once

#include <string_view>

namespace province::core {

[[nodiscard]] constexpr std::string_view version() noexcept {
    return "0.1.0-dev";
}

} // namespace province::core

