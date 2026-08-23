#include "smoke_test_groups.hpp"

#include "province/core/command_processor.hpp"
#include "province/core/game_command.hpp"
#include "province/core/scenario_loader.hpp"

#include <cstdint>
#include <iostream>

bool run_ai_smoke_tests() {
    using namespace province::core;

    GameState state = ScenarioLoader::load(
        "game/data",
        GameClock{1000, 1},
        [](const std::uint32_t) { return std::uint32_t{0}; }
    );
    CommandProcessor processor;
    processor.enable_ai(CountryId{"auroria"});
    const CommandResult result = processor.execute(state, AdvanceTurnCommand{1});
    if (!result.accepted) {
        std::cerr << "AI-enabled generated turn was rejected\n";
        return false;
    }
    std::size_t human_armies = 0;
    std::size_t neutral_armies = 0;
    for (const auto& [army_id, army] : state.armies()) {
        static_cast<void>(army_id);
        if (army.owner_id == CountryId{"auroria"}) ++human_armies;
        if (army.owner_id == CountryId{"neutral"}) ++neutral_armies;
    }
    if (human_armies != 0 || neutral_armies != 17) {
        std::cerr << "AI controlled the human or altered neutral guards\n";
        return false;
    }
    return true;
}
