env = Environment()

if env["PLATFORM"] == "win32":
    env.Append(CXXFLAGS=["/std:c++20", "/EHsc", "/W4", "/permissive-"])
else:
    env.Append(CXXFLAGS=["-std=c++20", "-Wall", "-Wextra", "-Wpedantic"])

env.Append(CPPPATH=["core/include"])

core_sources = Glob("core/src/*.cpp")
core_library = env.StaticLibrary(target="build/lib/province_core", source=core_sources)

test_program = env.Program(
    target="build/bin/province_core_tests",
    source=["tests/core/core_smoke_test.cpp"],
    LIBS=[core_library],
)

Alias("tests", test_program)

godot_cpp_env = SConscript("third_party/godot-cpp/SConstruct")
godot_env = godot_cpp_env.Clone()
godot_env.Append(CPPPATH=["core/include", "bridge/src"])
if godot_env["platform"] == "windows":
    godot_env["CXXFLAGS"] = [
        flag for flag in godot_env["CXXFLAGS"] if not str(flag).startswith("/std:c++")
    ]
    godot_env.Append(CXXFLAGS=["/std:c++20", "/permissive-"])
else:
    godot_env["CXXFLAGS"] = [
        flag for flag in godot_env["CXXFLAGS"] if not str(flag).startswith("-std=")
    ]
    godot_env.Append(CXXFLAGS=["-std=c++20"])

bridge_sources = Glob("bridge/src/*.cpp") + core_sources
bridge_library = godot_env.SharedLibrary(
    target="game/bin/province_bridge{}{}".format(
        godot_env["suffix"], godot_env["SHLIBSUFFIX"]
    ),
    source=bridge_sources,
)
godot_env.NoCache(bridge_library)

Alias("bridge", bridge_library)
Default(test_program, bridge_library)
