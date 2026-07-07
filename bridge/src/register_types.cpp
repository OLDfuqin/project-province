#include "register_types.hpp"

#include "province_bridge.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

void initialize_province_bridge(const godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(province::bridge::ProvinceBridge);
}

void uninitialize_province_bridge(const godot::ModuleInitializationLevel level) {
    if (level != godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {

GDExtensionBool GDE_EXPORT province_bridge_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library,
    GDExtensionInitialization* initialization
) {
    godot::GDExtensionBinding::InitObject init_object{
        get_proc_address,
        library,
        initialization,
    };
    init_object.register_initializer(initialize_province_bridge);
    init_object.register_terminator(uninitialize_province_bridge);
    init_object.set_minimum_library_initialization_level(
        godot::MODULE_INITIALIZATION_LEVEL_SCENE
    );
    return init_object.init();
}

} // extern "C"

