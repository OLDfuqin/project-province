#pragma once

#include <stdexcept>
#include <string>

namespace province::core {

class DataLoadError final : public std::runtime_error {
public:
    explicit DataLoadError(const std::string& message);
};

} // namespace province::core
