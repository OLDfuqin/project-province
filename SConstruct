import os

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
Default(test_program)

