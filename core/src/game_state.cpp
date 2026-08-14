#include "province/core/game_state.hpp"

#include <algorithm>
#include <set>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>

namespace province::core {

GameState::GameState(GameClock clock) : clock_{std::move(clock)} {}

void GameState::add_country(Country country) {
    if (country.name.empty()) {
        throw std::invalid_argument{"country name cannot be empty"};
    }
    if (country.code.empty()) {
        throw std::invalid_argument{"country code cannot be empty"};
    }
    if (country.treasury < 0) {
        throw std::invalid_argument{"country treasury cannot be negative at creation"};
    }

    const auto [iterator, inserted] = countries_.emplace(country.id, std::move(country));
    if (!inserted) {
        throw std::invalid_argument{"duplicate country ID: " + iterator->first.value()};
    }
    technologies_.emplace(iterator->first, CountryTechnology{});
}

void GameState::add_province(Province province) {
    if (province.name.empty()) {
        throw std::invalid_argument{"province name cannot be empty"};
    }
    if (province.population < 0 || province.recruitable_population < 0) {
        throw std::invalid_argument{"province population cannot be negative"};
    }
    if (province.recruitable_population > province.population) {
        throw std::invalid_argument{"recruitable population cannot exceed total population"};
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

const CountryTechnology* GameState::find_technology(const CountryId& country_id) const noexcept {
    const auto iterator = technologies_.find(country_id);
    return iterator == technologies_.end() ? nullptr : &iterator->second;
}

CountryTechnology* GameState::find_technology(const CountryId& country_id) noexcept {
    const auto iterator = technologies_.find(country_id);
    return iterator == technologies_.end() ? nullptr : &iterator->second;
}

const std::map<CountryId, CountryTechnology>& GameState::technologies() const noexcept {
    return technologies_;
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
    const std::int64_t formation_number = next_formation_number(owner_id);
    const auto [iterator, inserted] = armies_.emplace(
        id,
        Army{
            id,
            owner_id,
            province_id,
            manpower,
            0,
            std::nullopt,
            true,
            "max",
            formation_number,
        }
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

std::int64_t GameState::next_formation_number(const CountryId& owner_id) const {
    if (find_country(owner_id) == nullptr) {
        throw std::invalid_argument{"army owner does not exist"};
    }
    std::set<std::int64_t> used_numbers;
    for (const auto& [army_id, army] : armies_) {
        static_cast<void>(army_id);
        if (army.owner_id == owner_id && army.formation_number > 0) {
            used_numbers.insert(army.formation_number);
        }
    }
    std::int64_t candidate = 1;
    while (used_numbers.contains(candidate)) {
        ++candidate;
    }
    return candidate;
}

std::string GameState::army_display_name(const ArmyId& army_id) const {
    const Army* army = find_army(army_id);
    if (army == nullptr) {
        throw std::invalid_argument{"army does not exist"};
    }
    const Country* country = find_country(army->owner_id);
    if (country == nullptr) {
        throw std::logic_error{"army owner does not exist"};
    }
    return country->code + "\xC2\xB7\xE7\xAC\xAC" +
        std::to_string(army->formation_number) + "\xE5\x86\x9B";
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

void GameState::transfer_province_ownership(
    const ProvinceId& province_id,
    const CountryId& new_owner_id
) {
    Province* province = find_province(province_id);
    if (province == nullptr || find_country(new_owner_id) == nullptr) {
        throw std::invalid_argument{"province and new owner must exist"};
    }
    province->owner_id = new_owner_id;
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

    std::set<std::string> country_codes;
    for (const auto& [country_id, country] : countries_) {
        if (country.code.empty()) {
            issues.push_back("country '" + country_id.value() + "' has an empty code");
        } else if (!country_codes.insert(country.code).second) {
            issues.push_back("country '" + country_id.value() + "' has a duplicate code");
        }
    }

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
    std::map<CountryId, std::set<std::int64_t>> formation_numbers;
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
        if (army.formation_number <= 0) {
            issues.push_back("army '" + army_id.value() + "' has a non-positive formation number");
        } else if (!formation_numbers[army.owner_id]
                        .insert(army.formation_number)
                        .second) {
            issues.push_back("army '" + army_id.value() + "' has a duplicate formation number");
        }
        if (army.movement_points < 0) {
            issues.push_back("army '" + army_id.value() + "' has negative movement points");
        }
        if (army.advance_target.has_value() &&
            !provinces_.contains(*army.advance_target)) {
            issues.push_back("army '" + army_id.value() + "' has an unknown advance target");
        }
        if (army.advance_strategy != "max" && army.advance_strategy != "one_step" &&
            army.advance_strategy != "stop_before_enemy") {
            issues.push_back("army '" + army_id.value() + "' has an unknown advance strategy");
        }
    }
    for (const auto& [country_id, country] : countries_) {
        static_cast<void>(country);
        if (!technologies_.contains(country_id)) {
            issues.push_back("country '" + country_id.value() + "' has no technology state");
        }
    }
    for (const auto& [country_id, technology] : technologies_) {
        if (!countries_.contains(country_id)) {
            issues.push_back("technology state references unknown country '" + country_id.value() + "'");
        }
        const bool invalid_level =
            technology.economy_level < 0 ||
            technology.military_level < 0 ||
            technology.roads_level < 0 ||
            technology.economy_level > CountryTechnology::maximum_level ||
            technology.military_level > CountryTechnology::maximum_level ||
            technology.roads_level > CountryTechnology::maximum_level;
        if (invalid_level) {
            issues.push_back("country '" + country_id.value() + "' has an invalid technology level");
        }
    }
    for (const auto& [province_id, controller_id] : occupations_) {
        if (!provinces_.contains(province_id) || !countries_.contains(controller_id)) {
            issues.push_back("occupation references an unknown province or country");
        }
    }
    return issues;
}

} // namespace province::core
