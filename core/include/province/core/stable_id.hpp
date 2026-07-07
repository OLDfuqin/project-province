#pragma once

#include <compare>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>

namespace province::core {

template <typename Tag>
class StableId final {
public:
    explicit StableId(std::string value) : value_{std::move(value)} {
        if (!is_valid(value_)) {
            throw std::invalid_argument{
                "stable ID must contain only lowercase ASCII letters, digits, '_' or '-'"
            };
        }
    }

    [[nodiscard]] const std::string& value() const noexcept {
        return value_;
    }

    [[nodiscard]] static bool is_valid(const std::string_view value) noexcept {
        if (value.empty()) {
            return false;
        }

        for (const char character : value) {
            const bool is_lowercase = character >= 'a' && character <= 'z';
            const bool is_digit = character >= '0' && character <= '9';
            if (!is_lowercase && !is_digit && character != '_' && character != '-') {
                return false;
            }
        }
        return true;
    }

    auto operator<=>(const StableId&) const = default;

private:
    std::string value_;
};

struct CountryIdTag;
struct ProvinceIdTag;
struct ArmyIdTag;

using CountryId = StableId<CountryIdTag>;
using ProvinceId = StableId<ProvinceIdTag>;
using ArmyId = StableId<ArmyIdTag>;

} // namespace province::core
