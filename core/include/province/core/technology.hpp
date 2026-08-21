#pragma once

#include <cstdint>

namespace province::core {

enum class TechnologyTrack : std::uint8_t {
    economy,
    military,
    roads,
};

struct CountryTechnology final {
    static constexpr std::int32_t economy_maximum_level = 3;
    static constexpr std::int32_t military_maximum_level = 8;
    static constexpr std::int32_t roads_maximum_level = 4;

    std::int32_t economy_level{};
    std::int32_t military_level{};
    std::int32_t roads_level{};

    [[nodiscard]] static constexpr std::int32_t maximum_level(TechnologyTrack track) noexcept {
        switch (track) {
        case TechnologyTrack::economy:
            return economy_maximum_level;
        case TechnologyTrack::military:
            return military_maximum_level;
        case TechnologyTrack::roads:
            return roads_maximum_level;
        }
        return economy_maximum_level;
    }

    [[nodiscard]] std::int32_t level(TechnologyTrack track) const noexcept {
        switch (track) {
        case TechnologyTrack::economy:
            return economy_level;
        case TechnologyTrack::military:
            return military_level;
        case TechnologyTrack::roads:
            return roads_level;
        }
        return 0;
    }

    [[nodiscard]] std::int32_t& level(TechnologyTrack track) noexcept {
        switch (track) {
        case TechnologyTrack::economy:
            return economy_level;
        case TechnologyTrack::military:
            return military_level;
        case TechnologyTrack::roads:
            return roads_level;
        }
        return economy_level;
    }
};

} // namespace province::core
