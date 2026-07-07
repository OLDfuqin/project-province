#include "province/core/game_state.hpp"

#include <algorithm>
#include <stdexcept>
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

const Province* GameState::find_province(const ProvinceId& id) const noexcept {
    const auto iterator = provinces_.find(id);
    return iterator == provinces_.end() ? nullptr : &iterator->second;
}

std::size_t GameState::country_count() const noexcept {
    return countries_.size();
}

std::size_t GameState::province_count() const noexcept {
    return provinces_.size();
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
    return issues;
}

} // namespace province::core

