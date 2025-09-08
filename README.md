# ODB-CMake

A CMake module for using the ODB ORM compiler

## Modules

- **FindODB.cmake**  
  CMake module to locate the ODB compiler and libraries, and provide imported targets for linking.
- **UseODB.cmake**  
  CMake module to automate code generation from your `.hxx` model headers using the `odb_compile()` function.

---

## Quick Start

### 1. Add Modules to Your Project

Place `FindODB.cmake` and `UseODB.cmake` in your project's `cmake/` directory (or any directory of your choice).

In your `CMakeLists.txt`:

```cmake
set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})
```

### 2. Find the ODB Package

Specify the required database backends (e.g., PostgreSQL, SQLite):

```cmake
find_package(ODB REQUIRED COMPONENTS pgsql sqlite)
```

Supported components (case-insensitive): `pgsql`, `mysql`, `sqlite`, `oracle`, `mssql`, `boost`, `qt`.

### 3. Add Your Target

Define your executable/library as usual:

```cmake
add_executable(my_app main.cpp)
```

### 4. Generate ODB Sources

Use the `odb_compile()` function to generate sources from your model headers:

```cmake
find_package(ODB REQUIRED COMPONENTS pgsql sqlite)

odb_compile(
  TARGETS my_app
  DATABASES pgsql sqlite
  SOURCES my_model.hxx another_model.hxx
  MULTI_DATABASE dynamic # Enable multi-database mode
  # Optional arguments:
  # OUTPUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/odb_gen
  # PROFILES boost qt
  # STANDARD c++17
)
```

This will:

- Run the ODB compiler on your header files when building.
- Add the generated `.cxx` files to your target.
- Set up include directories and link the required runtime libraries.

### 5. Build

Just build your project as usual:

```sh
cmake -S . -B build
cmake --build build
```

---

## Advanced Usage

- For multi-database support (sharing model code across DBs), set `DATABASES` to multiple backends, or use `DB` for a single backend.
- Control ODB codegen details with options like `GENERATE_QUERY`, `GENERATE_SESSION`, `GENERATE_SCHEMA`, `PROFILES`, etc.
- All generated files are placed in `OUTPUT_DIR` (default: `<binary dir>/odb_gen`).

See the comments in `UseODB.cmake` for all available options.

---

## Example

```cmake
find_package(ODB REQUIRED COMPONENTS sqlite)

add_executable(myapp main.cpp)

odb_compile(
  TARGET myapp
  DB sqlite
  SOURCES person.hxx address.hxx
  GENERATE_QUERY
  PROFILES boost
)

target_link_libraries(myapp PRIVATE ODB::ODB ODB::SQLite)
```

---

## Requirements

- ODB compiler and libraries must be installed and discoverable in standard locations or by setting `ODB_ROOT`/`ODB_DIR` environment variables.
- CMake 3.13+ recommended.

---

## References

- [ODB Documentation](https://www.codesynthesis.com/products/odb/doc/odb.xhtml)
- [ODB Manual](https://www.codesynthesis.com/products/odb/doc/manual.xhtml)
