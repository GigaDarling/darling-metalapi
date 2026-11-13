// SPDX-License-Identifier: GPL-3.0-or-later
// Standalone test client for Indium's existing SPIR-V + reflection interface.
// The companion script verifies that these fixtures declare no resource bindings.
#include <indium/device.hpp>
#include <indium/init.hpp>
#include <indium/library.hpp>

#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static std::vector<uint32_t> readModule(const char* path) {
    std::ifstream input(path, std::ios::binary | std::ios::ate);
    const auto size = input.tellg();
    if (!input || size < 20 || size > 64 * 1024 * 1024 || size % 4 != 0)
        throw std::runtime_error("invalid SPIR-V file size");
    std::vector<uint32_t> module(static_cast<size_t>(size) / 4);
    // Reading the object representation into allocated uint32_t storage is
    // deliberate: Vulkan requires word-aligned SPIR-V, rather than a char buffer.
    if (!input.seekg(0).read(reinterpret_cast<char*>(module.data()), size))
        throw std::runtime_error("cannot read SPIR-V file");
    return module;
}

static void checkLibrary(const char* stage, const char* name, const char* path) {
    Indium::FunctionType type;
    if (std::string(stage) == "vertex")
        type = Indium::FunctionType::Vertex;
    else if (std::string(stage) == "fragment")
        type = Indium::FunctionType::Fragment;
    else
        throw std::runtime_error("expected vertex or fragment stage");

    auto words = readModule(path);
    auto device = Indium::createSystemDefaultDevice();
    if (!device)
        throw std::runtime_error("no usable Vulkan device");

    Indium::LibraryReflection reflection;
    reflection.functions[name].functionType = type;
    std::string error;
    auto library = device->newLibrary(words.data(), words.size() * sizeof(uint32_t), reflection, &error);
    if (!library)
        throw std::runtime_error("library loading failed: " + error);

    auto function = library->newFunction(name);
    if (!function || function->functionType() != type)
        throw std::runtime_error("loaded function has the wrong name or stage");
    if (library->newFunction("baseline_missing_entry"))
        throw std::runtime_error("missing function was accepted");

    auto invalid = reflection;
    invalid.functions.clear();
    if (device->newLibrary(words.data(), words.size() * sizeof(uint32_t), invalid, &error))
        throw std::runtime_error("empty reflection was accepted");
    invalid.functions["baseline_missing_entry"].functionType = type;
    if (device->newLibrary(words.data(), words.size() * sizeof(uint32_t), invalid, &error))
        throw std::runtime_error("nonexistent entry point was accepted");
    if (device->newLibrary(words.data(), 8, reflection, &error))
        throw std::runtime_error("truncated module was accepted");

    std::cout << "PASS " << stage << ' ' << name << ": loaded on " << device->name()
              << "; missing function, invalid reflection and truncated module rejected\n";
}

int main(int argc, char** argv) {
    if (argc != 4) {
        std::cerr << "Usage: library-probe <vertex|fragment> <entry> <file.spv>\n";
        return 2;
    }
    bool initialized = false;
    try {
        Indium::init(nullptr, 0, false);
        initialized = true;
        checkLibrary(argv[1], argv[2], argv[3]);
        Indium::finit();
        return 0;
    } catch (const std::exception& error) {
        if (initialized)
            Indium::finit();
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
