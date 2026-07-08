#include "province/core/peace_system.hpp"

#include <utility>

namespace province::core {

PeaceSettlementResult PeaceSystem::settle(
    GameState& state,
    const CountryId& country_a,
    const CountryId& country_b,
    const PeaceSettlementPolicy policy
) const {
    PeaceSettlementResult result{false, {}, country_a, country_b, policy, {}, {}};
    if (country_a == country_b) {
        result.error = "a country cannot make peace with itself";
        return result;
    }
    if (state.find_country(country_a) == nullptr || state.find_country(country_b) == nullptr) {
        result.error = "both peace participants must exist";
        return result;
    }
    if (!state.are_at_war(country_a, country_b)) {
        result.error = "countries are not at war";
        return result;
    }

    const auto occupations = state.occupations();
    for (const auto& [province_id, controller] : occupations) {
        Province* province = state.find_province(province_id);
        if (province == nullptr) {
            continue;
        }
        const bool belongs_to_war =
            (province->owner_id == country_a && controller == country_b) ||
            (province->owner_id == country_b && controller == country_a);
        if (!belongs_to_war) {
            continue;
        }

        PeaceProvinceSettlement settlement{
            province_id,
            province->owner_id,
            controller,
            province->owner_id,
        };
        if (policy == PeaceSettlementPolicy::annex_occupied_provinces) {
            state.transfer_province_ownership(province_id, controller);
            settlement.legal_owner_after = controller;
        } else {
            state.clear_occupation(province_id);
        }
        result.provinces.push_back(std::move(settlement));
    }

    state.set_diplomatic_status(country_a, country_b, DiplomaticStatus::peace);

    std::vector<ArmyId> army_ids;
    army_ids.reserve(state.army_count());
    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army);
        army_ids.push_back(army_id);
    }
    for (const ArmyId& army_id : army_ids) {
        Army* army = state.find_army(army_id);
        if (army == nullptr || state.controller_of(army->province_id) == army->owner_id) {
            continue;
        }
        const ProvinceId origin = army->province_id;
        std::optional<ProvinceId> destination;
        for (const auto& [province_id, province] : state.provinces()) {
            static_cast<void>(province);
            if (state.controller_of(province_id) == army->owner_id) {
                destination = province_id;
                break;
            }
        }
        if (destination.has_value()) {
            army->province_id = *destination;
        } else {
            state.remove_army(army_id);
        }
        result.armies.push_back(ArmyRepatriation{
            army_id,
            origin,
            destination,
            !destination.has_value(),
        });
    }

    result.accepted = true;
    return result;
}

} // namespace province::core
