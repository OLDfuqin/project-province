env = Environment()

VariantDir("build/obj/core", "core/src", duplicate=0)
VariantDir("build/obj/bridge", "bridge/src", duplicate=0)
VariantDir("build/obj/tests/core", "tests/core", duplicate=0)

if env["PLATFORM"] == "win32":
    env.Append(CXXFLAGS=["/std:c++20", "/EHsc", "/W4", "/permissive-"])
else:
    env.Append(CXXFLAGS=["-std=c++20", "-Wall", "-Wextra", "-Wpedantic"])

env.Append(CPPPATH=["core/include", "third_party"])

core_sources = Glob("build/obj/core/*.cpp")
core_library = env.StaticLibrary(target="build/lib/province_core", source=core_sources)

test_program = env.Program(
    target="build/bin/province_core_tests",
    source=[
        "build/obj/tests/core/ai_smoke_test.cpp",
        "build/obj/tests/core/battle_calculator_test.cpp",
        "build/obj/tests/core/core_smoke_test.cpp",
        "build/obj/tests/core/grid_map_layout_test.cpp",
        "build/obj/tests/core/map_cell_generator_test.cpp",
        "build/obj/tests/core/map_scenario_generator_test.cpp",
        "build/obj/tests/core/neutral_combat_test.cpp",
        "build/obj/tests/core/neutral_population_test.cpp",
        "build/obj/tests/core/order_system_test.cpp",
        "build/obj/tests/core/save_game_smoke_test.cpp",
    ],
    LIBS=[core_library],
)

Alias("tests", test_program)

godot_cpp_env = SConscript("third_party/godot-cpp/SConstruct")
godot_env = godot_cpp_env.Clone()
godot_env.Append(CPPPATH=["core/include", "bridge/src", "third_party"])
if godot_env["platform"] == "windows":
    godot_env["CXXFLAGS"] = [
        flag for flag in godot_env["CXXFLAGS"] if not str(flag).startswith("/std:c++")
    ]
    godot_env.Append(CXXFLAGS=["/std:c++20", "/EHsc", "/permissive-"])
else:
    godot_env["CXXFLAGS"] = [
        flag for flag in godot_env["CXXFLAGS"] if not str(flag).startswith("-std=")
    ]
    godot_env.Append(CXXFLAGS=["-std=c++20"])

bridge_sources = Glob("build/obj/bridge/*.cpp") + core_sources
bridge_library = godot_env.SharedLibrary(
    target="game/bin/province_bridge{}{}".format(
        godot_env["suffix"], godot_env["SHLIBSUFFIX"]
    ),
    source=bridge_sources,
)
godot_env.NoCache(bridge_library)

Alias("bridge", bridge_library)
Default(test_program, bridge_library)
