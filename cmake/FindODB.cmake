# ===================================================================================
# FindODB.cmake
#
# Finds the ODB compiler and runtime libraries (core and optional components).
#
# Imported targets:
#   ODB::Compiler     - ODB compiler executable
#   ODB::ODB          - Core ODB runtime library
#   ODB::PostgreSQL   - PostgreSQL support library
#   ODB::MySQL        - MySQL support library
#   ODB::SQLite       - SQLite support library
#   ODB::Oracle       - Oracle support library
#   ODB::MSSQL        - MS SQL Server support library
#   ODB::Boost        - Boost profile library
#   ODB::Qt           - Qt profile library
#
# Result variables:
#   ODB_FOUND
#   ODB_COMPILER            (alias: ODB_EXECUTABLE)
#   ODB_VERSION
#   ODB_INCLUDE_DIRS
#   ODB_LIBRARIES
#
# Supported components in find_package:
#   pgsql, mysql, sqlite, oracle, mssql, boost, qt
#
# Usage:
#   set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})
#   find_package(ODB REQUIRED COMPONENTS pgsql sqlite)
#   # Then include UseODB.cmake and call odb_compile()
# ===================================================================================

include_guard(GLOBAL)
include(UseODB)
include(FindPackageHandleStandardArgs)

# Initialize
set(ODB_FOUND FALSE)
set(ODB_INCLUDE_DIRS "")
set(ODB_LIBRARIES "")

# Search roots
set(_ODB_SEARCH_PATHS
  ${ODB_ROOT}
  $ENV{ODB_ROOT}
  ${ODB_DIR}
  $ENV{ODB_DIR}
  /usr
  /usr/local
  /opt/odb
  /opt/local
  "C:/Program Files"
  "C:/Program Files (x86)"
)

# --------------------------
# Find ODB compiler (executable)
# --------------------------
find_program(ODB_COMPILER
  NAMES odb
  HINTS ${_ODB_SEARCH_PATHS}
  PATH_SUFFIXES bin
  DOC "Path to ODB compiler executable"
)

# Compatibility alias
set(ODB_EXECUTABLE "${ODB_COMPILER}")

set(ODB_VERSION "")
set(_ODB_VERSION_MM "")

if(ODB_COMPILER)
  execute_process(
    COMMAND ${ODB_COMPILER} --version
    OUTPUT_VARIABLE _ODB_VERSION_OUT
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(_ODB_VERSION_OUT MATCHES "ODB[^\n]*compiler[^\n]*([0-9]+\\.[0-9]+\\.[0-9]+)")
    set(ODB_VERSION "${CMAKE_MATCH_1}")
    string(REGEX MATCH "^([0-9]+\\.[0-9]+)" _ODB_VERSION_MM "${ODB_VERSION}")
  endif()

  if(NOT TARGET ODB::Compiler)
    add_executable(ODB::Compiler IMPORTED GLOBAL)
    set_target_properties(ODB::Compiler PROPERTIES
      IMPORTED_LOCATION "${ODB_COMPILER}"
    )
  endif()
endif()

# --------------------------
# Find ODB core include/lib
# --------------------------
find_path(ODB_INCLUDE_DIR
  NAMES odb/core.hxx
  HINTS ${_ODB_SEARCH_PATHS}
  PATH_SUFFIXES include
  DOC "ODB include directory (must contain 'odb/core.hxx')"
)

# Library names may be: odb, odb-2.5, etc.
set(_ODB_CORE_NAMES odb)
if(_ODB_VERSION_MM)
  list(APPEND _ODB_CORE_NAMES "odb-${_ODB_VERSION_MM}")
endif()

find_library(ODB_LIBRARY
  NAMES ${_ODB_CORE_NAMES}
  HINTS ${_ODB_SEARCH_PATHS}
  PATH_SUFFIXES lib lib64 lib/x86_64-linux-gnu
  DOC "ODB core runtime library"
)

if(ODB_LIBRARY AND ODB_INCLUDE_DIR)
  list(APPEND ODB_INCLUDE_DIRS "${ODB_INCLUDE_DIR}")
  list(APPEND ODB_LIBRARIES "${ODB_LIBRARY}")

  if(NOT TARGET ODB::ODB)
    add_library(ODB::ODB UNKNOWN IMPORTED GLOBAL)
    set_target_properties(ODB::ODB PROPERTIES
      IMPORTED_LOCATION "${ODB_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${ODB_INCLUDE_DIR}"
    )
  endif()

  # Backward-compat alias
  if(NOT TARGET ODB::libodb)
    add_library(ODB::libodb ALIAS ODB::ODB)
  endif()
endif()

# --------------------------
# Components
# --------------------------
# Map: component ; base library name ; pretty target name ; header to probe
set(_ODB_COMPONENTS
  "pgsql:odb-pgsql:PostgreSQL:odb/pgsql/database.hxx"
  "mysql:odb-mysql:MySQL:odb/mysql/database.hxx"
  "sqlite:odb-sqlite:SQLite:odb/sqlite/database.hxx"
  "oracle:odb-oracle:Oracle:odb/oracle/database.hxx"
  "mssql:odb-mssql:MSSQL:odb/mssql/database.hxx"
  "boost:odb-boost:Boost:odb/boost/version.hxx"
  "qt:odb-qt:Qt:odb/qt/version.hxx"
)

# Helper: find component by name
function(_odb_find_component comp)
  #Outputs (via PARENT_SCOPE): _ODB_COMP_LIB _ODB_COMP_TGT _ODB_COMP_HDR
  # Clear outputs
  set(_ODB_COMP_LIB "" PARENT_SCOPE)
  set(_ODB_COMP_TGT "" PARENT_SCOPE)
  set(_ODB_COMP_HDR "" PARENT_SCOPE)
  # REGEX matches
  foreach(_entry IN LISTS _ODB_COMPONENTS)
   if(_entry MATCHES "^${comp}:([^:]+):([^:]+):(.+)$") 
    set(_ODB_COMP_LIB "${CMAKE_MATCH_1}" PARENT_SCOPE)
    set(_ODB_COMP_TGT "${CMAKE_MATCH_2}" PARENT_SCOPE)
    set(_ODB_COMP_HDR "${CMAKE_MATCH_3}" PARENT_SCOPE)
   endif()
  endforeach()
endfunction()

foreach(_comp IN LISTS ODB_FIND_COMPONENTS)
  _odb_find_component("${_comp}")
  if(NOT _ODB_COMP_LIB)
    message(WARNING "FindODB: Unknown component requested: ${_comp}")
    string(TOUPPER "${_comp}" _COMP_UPPER)
    set(ODB_${_COMP_UPPER}_FOUND FALSE)
    continue()
  endif()

  # Candidate library names (with/without major.minor)
  set(_CANDIDATE_LIBS "${_ODB_COMP_LIB}")
  if(_ODB_VERSION_MM)
    list(APPEND _CANDIDATE_LIBS "${_ODB_COMP_LIB}-${_ODB_VERSION_MM}")
  endif()

  # Find library
  find_library(ODB_${_comp}_LIBRARY
    NAMES ${_CANDIDATE_LIBS}
    HINTS ${_ODB_SEARCH_PATHS}
    PATH_SUFFIXES lib lib64 lib/x86_64-linux-gnu
    DOC "ODB ${_comp} library"
  )

  # Include directory for the component (fallback to core include dir)
  set(ODB_${_comp}_INCLUDE_DIR "")
  if(_ODB_COMP_HDR)
    find_path(ODB_${_comp}_INCLUDE_DIR
      NAMES ${_ODB_COMP_HDR}
      HINTS ${_ODB_SEARCH_PATHS}
      PATH_SUFFIXES include
      DOC "ODB ${_comp} include directory"
    )
  endif()
  if(NOT ODB_${_comp}_INCLUDE_DIR AND ODB_INCLUDE_DIR)
    set(ODB_${_comp}_INCLUDE_DIR "${ODB_INCLUDE_DIR}")
  endif()

  if(ODB_${_comp}_LIBRARY)
    list(APPEND ODB_LIBRARIES "${ODB_${_comp}_LIBRARY}")
    if(ODB_${_comp}_INCLUDE_DIR)
      list(APPEND ODB_INCLUDE_DIRS "${ODB_${_comp}_INCLUDE_DIR}")
    endif()

    if(NOT TARGET ODB::${_ODB_COMP_TGT})
      add_library(ODB::${_ODB_COMP_TGT} UNKNOWN IMPORTED GLOBAL)
      set_target_properties(ODB::${_ODB_COMP_TGT} PROPERTIES
        IMPORTED_LOCATION "${ODB_${_comp}_LIBRARY}"
        INTERFACE_LINK_LIBRARIES ODB::ODB
      )
      if(ODB_${_comp}_INCLUDE_DIR)
        set_property(TARGET ODB::${_ODB_COMP_TGT} APPEND PROPERTY
          INTERFACE_INCLUDE_DIRECTORIES "${ODB_${_comp}_INCLUDE_DIR}"
        )
      endif()
    endif()

    # Compatibility alias
    if(NOT TARGET ODB::lib${_ODB_COMP_LIB})
      add_library(ODB::lib${_ODB_COMP_LIB} ALIAS ODB::${_ODB_COMP_TGT})
    endif()

    set(ODB_${_comp}_FOUND TRUE)
  else()
    set(ODB_${_comp}_FOUND FALSE)
    if(ODB_FIND_REQUIRED_${_comp})
      list(APPEND ODB_NOT_FOUND_COMPONENTS "${_comp}")
    endif()
  endif()
endforeach()

# Dedup include dirs
if(ODB_INCLUDE_DIRS)
  list(REMOVE_DUPLICATES ODB_INCLUDE_DIRS)
endif()

# Handle standard args and components

find_package_handle_standard_args(ODB
  REQUIRED_VARS ODB_COMPILER ODB_LIBRARY ODB_INCLUDE_DIR
  VERSION_VAR ODB_VERSION
  HANDLE_COMPONENTS
)

mark_as_advanced(
  ODB_COMPILER
  ODB_INCLUDE_DIR
  ODB_LIBRARY
)
