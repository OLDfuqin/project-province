#pragma once

#include "province/core/diplomacy.hpp"
#include "province/core/game_state.hpp"

#include <optional>
#include <vector>

namespace province::core {

struct PeaceProvinceSettlement final {
    ProvinceId province_id;
    CountryId legal_owner_before;
    CountryId controller_before;
    CountryId legal_owner_after;
};

struct ArmyRepatriation final {
    ArmyId army_id;
    ProvinceId origin;
    std::optional<ProvinceId> destination;
    bool disbanded{};
};

struct PeaceSettlementResult final {
    bool accepted{};
    std::string error;
    CountryId country_a;
    CountryId country_b;
    PeaceSettlementPolicy policy{PeaceSettlementPolicy::restore_legal_owners};
    std::vector<PeaceProvinceSettlement> provinces;
    std::vector<ArmyRepatriation> armies;
};

class PeaceSystem final {
public:
    [[nodiscard]] PeaceSettlementResult settle(
        GameState& state,
        const CountryId& country_a,
        const CountryId& country_b,
        PeaceSettlementPolicy policy
    ) const;
};

} // namespace province::core
