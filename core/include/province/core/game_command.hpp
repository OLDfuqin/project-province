#pragma once

#include "province/core/stable_id.hpp"
#include "province/core/diplomacy.hpp"
#include "province/core/technology.hpp"

#include <cstdint>
#include <variant>

namespace province::core {

struct AdvanceTurnCommand final {
    std::int32_t months{};
};

struct BuildRoadCommand final {
    CountryId country_id;
    ProvinceId province_a;
    ProvinceId province_b;
};

struct RecruitArmyCommand final {
    CountryId country_id;
    ProvinceId province_id;
    std::int64_t manpower{};
};

struct MoveArmyCommand final {
    ArmyId army_id;
    ProvinceId destination;
};

struct DeclareWarCommand final {
    CountryId aggressor_id;
    CountryId defender_id;
};

struct MakePeaceCommand final {
    CountryId country_a;
    CountryId country_b;
    PeaceSettlementPolicy policy{PeaceSettlementPolicy::restore_legal_owners};
};

struct ResearchTechnologyCommand final {
    CountryId country_id;
    TechnologyTrack track{TechnologyTrack::economy};
};

using GameCommand =
    std::variant<
        AdvanceTurnCommand,
        BuildRoadCommand,
        RecruitArmyCommand,
        MoveArmyCommand,
        DeclareWarCommand,
        MakePeaceCommand,
        ResearchTechnologyCommand
    >;

} // namespace province::core
