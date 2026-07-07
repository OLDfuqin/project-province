#pragma once

#include <cstdint>
#include <variant>

namespace province::core {

struct AdvanceTurnCommand final {
    std::int32_t months{};
};

using GameCommand = std::variant<AdvanceTurnCommand>;

} // namespace province::core

