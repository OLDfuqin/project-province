#include "province/core/game_state.hpp"

#include <algorithm>
#include <stdexcept>
#include <string>
#include <utility>

namespace province::core {

GameState::GameState(GameClock clock) : clock_{std::move(clock)} {}

void GameState::add_country(Country country) {
    if (country.name.empty()) {
        throw std::invalid_argument{"country name cannot be empty"};
    }
    if (country.treasury < 0) {
        throw std::invalid_argument{"country treasury cannot be negative at creation"};
    }

    const auto [iterator, inserted] = countries_.emplace(country.id, std::move(country));
    if (!inserted) {
        throw std::invalid_argument{"duplicate country ID: " + iterator->first.value()};
    }
}

void GameState::add_province(Province province) {
    if (province.name.empty()) {
        throw std::invalid_argument{"province name cannot be empty"};
    }
    if (province.population < 0 || province.soldier_population < 0) {
        throw std::invalid_argument{"province population cannot be negative"};
    }
    if (province.soldier_population > province.population) {
        throw std::invalid_argument{"soldier population cannot exceed total population"};
    }
    if (province.economy < 0) {
        throw std::invalid_argument{"province economy cannot be negative"};
    }
    if (province.population_growth_remainder < 0 ||
        province.population_growth_remainder >= 10'000) {
        throw std::invalid_argument{"population growth remainder must be in [0, 10000)"};
    }

    std::sort(province.neighbors.begin(), province.neighbors.end());
    const auto duplicate = std::adjacent_find(province.neighbors.begin(), province.neighbors.end());
    if (duplicate != province.neighbors.end()) {
        throw std::invalid_argument{"province neighbor list contains duplicates"};
    }
    if (std::binary_search(province.neighbors.begin(), province.neighbors.end(), province.id)) {
        throw std::invalid_argument{"province cannot be adjacent to itself"};
    }

    const auto [iterator, inserted] = provinces_.emplace(province.id, std::move(province));
    if (!inserted) {
        throw std::invalid_argument{"duplicate province ID: " + iterator->first.value()};
    }
}

const GameClock& GameState::clock() const noexcept {
    return clock_;
}

GameClock& GameState::clock() noexcept {
    return clock_;
}

const Country* GameState::find_country(const CountryId& id) const noexcept {
    const auto iterator = countries_.find(id);
    return iterator == countries_.end() ? nullptr : &iterator->second;
}

Country* GameState::find_country(const CountryId& id) noexcept {
    const auto iterator = countries_.find(id);
    return iterator == countries_.end() ? nullptr : &iterator->second;
}

const Province* GameState::find_province(const ProvinceId& id) const noexcept {
    const auto iterator = provinces_.find(id);
    return iterator == provinces_.end() ? nullptr : &iterator->second;
}

Province* GameState::find_province(const ProvinceId& id) noexcept {
    const auto iterator = provinces_.find(id);
    return iterator == provinces_.end() ? nullptr : &iterator->second;
}

std::size_t GameState::country_count() const noexcept {
    return countries_.size();
}

std::size_t GameState::province_count() const noexcept {
    return provinces_.size();
}

const std::map<CountryId, Country>& GameState::countries() const noexcept {
    return countries_;
}

const std::map<ProvinceId, Province>& GameState::provinces() const noexcept {
    return provinces_;
}

bool GameState::are_adjacent(
    const ProvinceId& province_a,
    const ProvinceId& province_b
) const noexcept {
    const Province* first = find_province(province_a);
    if (first == nullptr || find_province(province_b) == nullptr) {
        return false;
    }
    return std::binary_search(first->neighbors.begin(), first->neighbors.end(), province_b);
}

RoadLevel GameState::road_level(
    const ProvinceId& province_a,
    const ProvinceId& province_b
) const {
    const auto road = roads_.find(ProvinceConnectionKey{province_a, province_b});
    return road == roads_.end() ? RoadLevel::none : road->second;
}

void GameState::set_road_level(
    const ProvinceId& province_a,
    const ProvinceId& province_b,
    const RoadLevel level
) {
    if (!are_adjacent(province_a, province_b)) {
        throw std::invalid_argument{"roads can only be assigned to adjacent provinces"};
    }
    const ProvinceConnectionKey key{province_a, province_b};
    if (level == RoadLevel::none) {
        roads_.erase(key);
    } else {
        roads_.insert_or_assign(key, level);
    }
}

const std::map<ProvinceConnectionKey, RoadLevel>& GameState::roads() const noexcept {
    return roads_;
}

ArmyId GameState::create_army(
    const CountryId& owner_id,
    const ProvinceId& province_id,
    const std::int64_t manpower
) {
    if (find_country(owner_id) == nullptr || find_province(province_id) == nullptr) {
        throw std::invalid_argument{"army owner and province must exist"};
    }
    if (manpower <= 0) {
        throw std::invalid_argument{"army manpower must be positive"};
    }

    ArmyId id{"army_" + std::to_string(next_army_sequence_++)};
    const auto [iterator, inserted] = armies_.emplace(
        id,
        Army{id, owner_id, province_id, manpower, 0}
    );
    if (!inserted) {
        throw std::logic_error{"generated duplicate army ID"};
    }
    return iterator->first;
}

const Army* GameState::find_army(const ArmyId& id) const noexcept {
    const auto iterator = armies_.find(id);
    return iterator == armies_.end() ? nullptr : &iterator->second;
}

Army* GameState::find_army(const ArmyId& id) noexcept {
    const auto iterator = armies_.find(id);
    return iterator == armies_.end() ? nullptr : &iterator->second;
}

const std::map<ArmyId, Army>& GameState::armies() const noexcept {
    return armies_;
}

std::size_t GameState::army_count() const noexcept {
    return armies_.size();
}

void GameState::remove_army(const ArmyId& id) {
    if (armies_.erase(id) == 0) {
        throw std::invalid_argument{"army does not exist"};
    }
}

CountryId GameState::controller_of(const ProvinceId& province_id) const {
    const Province* province = find_province(province_id);
    if (province == nullptr) {
        throw std::invalid_argument{"province does not exist"};
    }
    const auto occupation = occupations_.find(province_id);
    return occupation == occupations_.end() ? province->owner_id : occupation->second;
}

void GameState::set_occupation(
    const ProvinceId& province_id,
    const CountryId& controller_id
) {
    const Province* province = find_province(province_id);
    if (province == nullptr || find_country(controller_id) == nullptr) {
        throw std::invalid_argument{"occupation province and controller must exist"};
    }
    if (province->owner_id == controller_id) {
        occupations_.erase(province_id);
    } else {
        occupations_.insert_or_assign(province_id, controller_id);
    }
}

void GameState::clear_occupation(const ProvinceId& province_id) {
    occupations_.erase(province_id);
}

const std::map<ProvinceId, CountryId>& GameState::occupations() const noexcept {
    return occupations_;
}

DiplomaticStatus GameState::diplomatic_status(
    const CountryId& country_a,
    const CountryId& country_b
) const {
    if (country_a == country_b) {
        return DiplomaticStatus::peace;
    }
    const auto relation = relations_.find(CountryRelationKey{country_a, country_b});
    return relation == relations_.end() ? DiplomaticStatus::peace : relation->second;
}

bool GameState::are_at_war(
    const CountryId& country_a,
    const CountryId& country_b
) const {
    return diplomatic_status(country_a, country_b) == DiplomaticStatus::war;
}

void GameState::set_diplomatic_status(
    const CountryId& country_a,
    const CountryId& country_b,
    const DiplomaticStatus status
) {
    if (country_a == country_b) {
        throw std::invalid_argument{"a country cannot have a diplomatic relation with itself"};
    }
    if (find_country(country_a) == nullptr || find_country(country_b) == nullptr) {
        throw std::invalid_argument{"both countries in a diplomatic relation must exist"};
    }
    const CountryRelationKey key{country_a, country_b};
    if (status == DiplomaticStatus::peace) {
        relations_.erase(key);
    } else {
        relations_.insert_or_assign(key, status);
    }
}

const std::map<CountryRelationKey, DiplomaticStatus>& GameState::relations() const noexcept {
    return relations_;
}

std::vector<std::string> GameState::validate() const {
    std::vector<std::string> issues;

    for (const auto& [province_id, province] : provinces_) {
        if (!countries_.contains(province.owner_id)) {
            issues.push_back(
                "province '" + province_id.value() + "' has unknown owner '" +
                province.owner_id.value() + "'"
            );
        }

        for (const ProvinceId& neighbor_id : province.neighbors) {
            const auto neighbor = provinces_.find(neighbor_id);
            if (neighbor == provinces_.end()) {
                issues.push_back(
                    "province '" + province_id.value() + "' has unknown neighbor '" +
                    neighbor_id.value() + "'"
                );
                continue;
            }

            const auto& reverse_neighbors = neighbor->second.neighbors;
            if (!std::binary_search(reverse_neighbors.begin(), reverse_neighbors.end(), province_id)) {
                issues.push_back(
                    "adjacency between '" + province_id.value() + "' and '" +
                    neighbor_id.value() + "' is not symmetric"
                );
            }
        }
    }
    for (const auto& [army_id, army] : armies_) {
        if (!countries_.contains(army.owner_id)) {
            issues.push_back("army '" + army_id.value() + "' has an unknown owner");
        }
        if (!provinces_.contains(army.province_id)) {
            issues.push_back("army '" + army_id.value() + "' has an unknown province");
        }
        if (army.manpower <= 0) {
            issues.push_back("army '" + army_id.value() + "' has non-positive manpower");
        }
    }
    return issues;
}

} // namespace province::core
