#pragma once

#include <cstdint>

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

namespace province::bridge {

class ProvinceBridge final : public godot::Node {
    GDCLASS(ProvinceBridge, godot::Node)

public:
    [[nodiscard]] godot::String get_core_version() const;
    [[nodiscard]] godot::Dictionary advance_date(
        std::int32_t year,
        std::int32_t month,
        std::int32_t months
    ) const;

protected:
    static void _bind_methods();
};

} // namespace province::bridge
