# ===================================================================================
# UseODB.cmake (fixed for proper multi-database/common handling)
#
# References:
#   - https://www.codesynthesis.com/products/odb/doc/odb.xhtml
#   - https://www.codesynthesis.com/products/odb/doc/manual.xhtml
#
# Function:
#   odb_compile(
#     TARGETS <target1> [<target2> ...]
#     [DB <db>] | [DATABASES <db1> <db2> ...]    # e.g. common, mysql, pgsql, sqlite, oracle, mssql
#     SOURCES <header1.hxx> [header2.hxx ...]
#
#     [OUTPUT_DIR <dir>]                          # default: ${CMAKE_CURRENT_BINARY_DIR}/odb_gen
#     [HEADER_SUFFIX <.hxx>] [SOURCE_SUFFIX <.cxx>] [INLINE_SUFFIX <.ixx>]
#     [STANDARD <c++17|17|20>]
#     [INCLUDE_DIRS <dirs...>]                    # extra -I passed to 'odb'
#     [DEFINITIONS <defs...>]                     # passed as -D<def>
#     [PROFILES <boost|qt ...>]                   # adds --profile and links ODB::Boost/ODB::Qt if present
#     [ODB_OPTIONS <opts...>]                     # raw passthrough options to 'odb'
#     [MULTI_DATABASE <dynamic|static>]           # explicitly enable multi-database mode
#
#     [GENERATE_QUERY] [GENERATE_SESSION] [GENERATE_SCHEMA]
#     [SCHEMA_FORMAT <sql|embedded|separate|...>]
#     [GENERATE_PREPARED]
#     [TABLE_PREFIX <prefix>]
#     [CHANGELOG <file>] [CHANGELOG_DIR <dir>]
#
#     [AT_ONCE]                                   # compile all SOURCES in one invocation
#     [OUT_VAR <var>]                             # PARENT_SCOPE var to receive generated .cxx list
#     [NO_AUTO_LINK]                              # do not auto-link ODB libraries
#   )
# ===================================================================================

include_guard(GLOBAL)

# Ensure ODB package is available
if(NOT TARGET ODB::Compiler)
  find_package(ODB QUIET)
endif()

function(odb_compile)
  set(_Options
    GENERATE_QUERY
    GENERATE_SESSION
    GENERATE_SCHEMA
    GENERATE_PREPARED
    AT_ONCE
    NO_AUTO_LINK
  )
  set(_OneValue
    DB
    OUTPUT_DIR
    HEADER_SUFFIX
    SOURCE_SUFFIX
    INLINE_SUFFIX
    SCHEMA_FORMAT
    STANDARD
    TABLE_PREFIX
    CHANGELOG
    CHANGELOG_DIR
    OUT_VAR
    MULTI_DATABASE
  )
  set(_MultiValue
    TARGETS
    SOURCES
    INCLUDE_DIRS
    DEFINITIONS
    DATABASES
    ODB_OPTIONS
    PROFILES
  )

  # Capture package include dirs before arg parsing to avoid name collision
  set(_PKG_ODB_INCLUDE_DIRS "${ODB_INCLUDE_DIRS}")

  cmake_parse_arguments(PARSE_ARGV 0 ODB "${_Options}" "${_OneValue}" "${_MultiValue}")

  # Validate
  if(NOT ODB_TARGETS)
    message(FATAL_ERROR "odb_compile: TARGETS is required")
  endif()
  if(NOT ODB_SOURCES)
    message(FATAL_ERROR "odb_compile: SOURCES is required")
  endif()
  if(NOT ODB_DB AND NOT ODB_DATABASES)
    message(FATAL_ERROR "odb_compile: DB or DATABASES must be specified")
  endif()
  foreach(_tgt IN LISTS ODB_TARGETS)
    if(NOT TARGET ${_tgt})
      message(FATAL_ERROR "odb_compile: TARGET '${_tgt}' does not exist")
    endif()
  endforeach()
  if(NOT TARGET ODB::Compiler)
    message(FATAL_ERROR "odb_compile: ODB::Compiler is not available. Make sure FindODB.cmake has been found: find_package(ODB REQUIRED).")
  endif()

  # Defaults
  if(NOT ODB_HEADER_SUFFIX)
    set(ODB_HEADER_SUFFIX ".hxx")
  endif()
  if(NOT ODB_SOURCE_SUFFIX)
    set(ODB_SOURCE_SUFFIX ".cxx")
  endif()
  if(NOT ODB_INLINE_SUFFIX)
    set(ODB_INLINE_SUFFIX ".ixx")
  endif()
  if(NOT ODB_OUTPUT_DIR)
    set(ODB_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/odb_gen")
  endif()
  if(NOT ODB_SCHEMA_FORMAT)
    set(ODB_SCHEMA_FORMAT "sql")
  endif()
  if(NOT ODB_CHANGELOG_DIR)
    set(ODB_CHANGELOG_DIR "${ODB_OUTPUT_DIR}")
  endif()

  # Normalize source list to absolute paths
  set(_INPUT_SOURCES "")
  foreach(_s IN LISTS ODB_SOURCES)
    if(IS_ABSOLUTE "${_s}")
      list(APPEND _INPUT_SOURCES "${_s}")
    else()
      list(APPEND _INPUT_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/${_s}")
    endif()
  endforeach()

  # Output dirs
  file(MAKE_DIRECTORY "${ODB_OUTPUT_DIR}")
  if(NOT "${ODB_OUTPUT_DIR}" STREQUAL "${ODB_CHANGELOG_DIR}")
    file(MAKE_DIRECTORY "${ODB_CHANGELOG_DIR}")
  endif()

  # Build ODB args
  set(_ODB_ARGS "")

  # Databases and multi-database mode
  set(_DB_LIST "")
  if(ODB_DATABASES)
    list(APPEND _DB_LIST ${ODB_DATABASES} common)
  elseif(ODB_DB)
    list(APPEND _DB_LIST ${ODB_DB})
  endif()
  list(REMOVE_DUPLICATES _DB_LIST)

  # Determine multi-database mode
  set(_MDB_MODE "")
  if(ODB_MULTI_DATABASE)
    string(TOLOWER "${ODB_MULTI_DATABASE}" _MDB_MODE)
    if(NOT _MDB_MODE MATCHES "^(dynamic|static)$")
      message(FATAL_ERROR "odb_compile: MULTI_DATABASE must be 'dynamic' or 'static', got '${ODB_MULTI_DATABASE}'.")
    endif()
  else()
    list(LENGTH _DB_LIST _db_count)
    if(_db_count GREATER 1)
      set(_MDB_MODE "dynamic") # auto
    else()
      # single item: if it is 'common', still need multi-database
      list(GET _DB_LIST 0 _only_db)
      if(_only_db STREQUAL "common")
        set(_MDB_MODE "dynamic") # auto
      endif()
    endif()
  endif()

  if(_MDB_MODE)
    list(APPEND _ODB_ARGS --multi-database "${_MDB_MODE}")
  endif()

  # Pass all databases, including 'common' (per manual §2.10)
  foreach(_db IN LISTS _DB_LIST)
    list(APPEND _ODB_ARGS -d "${_db}")
  endforeach()

  # C++ standard
  set(_STD_STR "")
  if(ODB_STANDARD)
    set(_STD_STR "${ODB_STANDARD}")
  elseif(CMAKE_CXX_STANDARD)
    set(_STD_STR "${CMAKE_CXX_STANDARD}")
  endif()
  if(_STD_STR)
    if(NOT _STD_STR MATCHES "^c\\+\\+[0-9]+$")
      set(_STD_STR "c++${_STD_STR}")
    endif()
    list(APPEND _ODB_ARGS --std "${_STD_STR}")
  endif()

  # Profiles (boost/qt/...)
  foreach(_p IN LISTS ODB_PROFILES)
    list(APPEND _ODB_ARGS --profile "${_p}")
  endforeach()

  # Generation toggles
  if(ODB_GENERATE_QUERY)
    list(APPEND _ODB_ARGS --generate-query)
  endif()
  if(ODB_GENERATE_SESSION)
    list(APPEND _ODB_ARGS --generate-session)
  endif()
  if(ODB_GENERATE_SCHEMA)
    list(APPEND _ODB_ARGS --generate-schema --schema-format "${ODB_SCHEMA_FORMAT}")
  endif()
  if(ODB_GENERATE_PREPARED)
    list(APPEND _ODB_ARGS --generate-prepared)
  endif()
  if(ODB_TABLE_PREFIX)
    list(APPEND _ODB_ARGS --table-prefix "${ODB_TABLE_PREFIX}")
  endif()
  if(ODB_CHANGELOG)
    list(APPEND _ODB_ARGS --changelog "${ODB_CHANGELOG}" --changelog-dir "${ODB_CHANGELOG_DIR}")
  else()
    list(APPEND _ODB_ARGS --changelog-dir "${ODB_CHANGELOG_DIR}")
  endif()

  # Include directories for code generator
  # - user-provided include dirs
  foreach(_inc IN LISTS ODB_INCLUDE_DIRS)
    list(APPEND _ODB_ARGS -I "${_inc}")
  endforeach()
  # - package include dirs from FindODB
  foreach(_inc IN LISTS _PKG_ODB_INCLUDE_DIRS)
    list(APPEND _ODB_ARGS -I "${_inc}")
  endforeach()
  # - target's own include dirs
  foreach(_tgt IN LISTS ODB_TARGETS)
    get_target_property(_t_incs ${_tgt} INCLUDE_DIRECTORIES)
    if(_t_incs)
      foreach(_inc IN LISTS _t_incs)
        list(APPEND _ODB_ARGS -I "${_inc}")
      endforeach()
    endif()
  endforeach()

  # Preprocessor definitions
  foreach(_def IN LISTS ODB_DEFINITIONS)
    list(APPEND _ODB_ARGS "-D${_def}")
  endforeach()
  # - target's own compile definitions
  foreach(_tgt IN LISTS ODB_TARGETS)
    get_target_property(_t_defs ${_tgt} COMPILE_DEFINITIONS)
    if(_t_defs)
      foreach(_def IN LISTS _t_defs)
        list(APPEND _ODB_ARGS "-D${_def}")
      endforeach()
    endif()
  endforeach()

  # Additional raw options
  foreach(_opt IN LISTS ODB_ODB_OPTIONS ODB_OPTIONS) # allow both spellings
    list(APPEND _ODB_ARGS "${_opt}")
  endforeach()

  # Output file configuration
  list(APPEND _ODB_ARGS
    --hxx-suffix "${ODB_HEADER_SUFFIX}"
    --cxx-suffix "${ODB_SOURCE_SUFFIX}"
    --ixx-suffix "${ODB_INLINE_SUFFIX}"
    --output-dir "${ODB_OUTPUT_DIR}"
  )

  # Compute generated files
  set(_ALL_GEN_CXX "")
  set(_ALL_GEN_FILES "")
  set(_ALL_INPUTS "${_INPUT_SOURCES}")
  
  if(ODB_AT_ONCE)
    foreach(_in IN LISTS _INPUT_SOURCES)
      get_filename_component(_stem "${_in}" NAME_WE)
      
      # Common files
      set(_gen_hxx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_HEADER_SUFFIX}")
      set(_gen_ixx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_INLINE_SUFFIX}")
      set(_gen_cxx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_SOURCE_SUFFIX}")
      list(APPEND _ALL_GEN_FILES "${_gen_hxx}" "${_gen_ixx}" "${_gen_cxx}")
      list(APPEND _ALL_GEN_CXX "${_gen_cxx}")
      
      # Database-specific files for multi-database mode
      if(_MDB_MODE)
        foreach(_db IN LISTS _DB_LIST)
          if(NOT _db STREQUAL "common")
            set(_db_hxx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_HEADER_SUFFIX}")
            set(_db_ixx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_INLINE_SUFFIX}")
            set(_db_cxx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_SOURCE_SUFFIX}")
            list(APPEND _ALL_GEN_FILES "${_db_hxx}" "${_db_ixx}" "${_db_cxx}")
            list(APPEND _ALL_GEN_CXX "${_db_cxx}")
          endif()
        endforeach()
      endif()
      
      # Schema files
      if(ODB_GENERATE_SCHEMA)
        foreach(_db IN LISTS _DB_LIST)
          if(NOT _db STREQUAL "common")
            set(_schema "${ODB_OUTPUT_DIR}/${_stem}-${_db}.sql")
            list(APPEND _ALL_GEN_FILES "${_schema}")
          endif()
        endforeach()
      endif()
    endforeach()
  
    add_custom_command(
      OUTPUT ${_ALL_GEN_FILES}
      COMMAND $<TARGET_FILE:ODB::Compiler> ${_ODB_ARGS} ${_INPUT_SOURCES}
      BYPRODUCTS ${_ALL_GEN_FILES}
      DEPENDS ${_ALL_INPUTS}
      COMMENT "ODB: Generating sources for ${ODB_TARGETS} (at-once)"
      VERBATIM
      COMMAND_EXPAND_LISTS
    )
  else()
    foreach(_in IN LISTS _INPUT_SOURCES)
      get_filename_component(_stem "${_in}" NAME_WE)
      
      # Collect all expected output files
      set(_this_gen_files "")
      
      # Common files
      set(_gen_hxx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_HEADER_SUFFIX}")
      set(_gen_ixx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_INLINE_SUFFIX}")
      set(_gen_cxx "${ODB_OUTPUT_DIR}/${_stem}-odb${ODB_SOURCE_SUFFIX}")
      list(APPEND _this_gen_files "${_gen_hxx}" "${_gen_ixx}" "${_gen_cxx}")
      list(APPEND _ALL_GEN_CXX "${_gen_cxx}")
      
      # Database-specific files for multi-database mode
      if(_MDB_MODE)
        foreach(_db IN LISTS _DB_LIST)
          if(NOT _db STREQUAL "common")
            set(_db_hxx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_HEADER_SUFFIX}")
            set(_db_ixx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_INLINE_SUFFIX}")
            set(_db_cxx "${ODB_OUTPUT_DIR}/${_stem}-odb-${_db}${ODB_SOURCE_SUFFIX}")
            list(APPEND _this_gen_files "${_db_hxx}" "${_db_ixx}" "${_db_cxx}")
            list(APPEND _ALL_GEN_CXX "${_db_cxx}")
          endif()
        endforeach()
      endif()
      
      # Schema files
      if(ODB_GENERATE_SCHEMA)
        foreach(_db IN LISTS _DB_LIST)
          if(NOT _db STREQUAL "common")
            set(_schema "${ODB_OUTPUT_DIR}/${_stem}-${_db}.sql")
            list(APPEND _this_gen_files "${_schema}")
          endif()
        endforeach()
      endif()
      
      add_custom_command(
        OUTPUT ${_this_gen_files}
        COMMAND $<TARGET_FILE:ODB::Compiler> ${_ODB_ARGS} "${_in}"
        BYPRODUCTS ${_this_gen_files}
        DEPENDS "${_in}"
        COMMENT "ODB: Generating sources for ${_stem}"
        VERBATIM
        COMMAND_EXPAND_LISTS
      )
      
      list(APPEND _ALL_GEN_FILES ${_this_gen_files})
    endforeach()
  endif()

  foreach(ODB_TARGET IN LISTS ODB_TARGETS)
    # Grouping target
    set(_GEN_TARGET "odb_gen_${ODB_TARGET}")
    add_custom_target(${_GEN_TARGET} DEPENDS ${_ALL_GEN_FILES})

    # Include generated sources and depend on generator
    target_sources(${ODB_TARGET} PRIVATE ${_ALL_GEN_CXX})
    add_dependencies(${ODB_TARGET} ${_GEN_TARGET})
    target_include_directories(${ODB_TARGET} PRIVATE "${ODB_OUTPUT_DIR}")
  endforeach()

  # Auto-link libraries (unless disabled). 'common' does not add any libs.
  if(NOT ODB_NO_AUTO_LINK)
    set(_NEED_LINK ODB::ODB)

    foreach(_db IN LISTS _DB_LIST)
      if(_db STREQUAL "mysql")
        list(APPEND _NEED_LINK ODB::MySQL)
      elseif(_db STREQUAL "pgsql")
        list(APPEND _NEED_LINK ODB::PostgreSQL)
      elseif(_db STREQUAL "sqlite")
        list(APPEND _NEED_LINK ODB::SQLite)
      elseif(_db STREQUAL "oracle")
        list(APPEND _NEED_LINK ODB::Oracle)
      elseif(_db STREQUAL "mssql")
        list(APPEND _NEED_LINK ODB::MSSQL)
      endif()
    endforeach()

    # Profiles -> libraries
    foreach(_p IN LISTS ODB_PROFILES)
      if(_p STREQUAL "boost")
        list(APPEND _NEED_LINK ODB::Boost)
      elseif(_p STREQUAL "qt")
        list(APPEND _NEED_LINK ODB::Qt)
      endif()
    endforeach()

    list(REMOVE_DUPLICATES _NEED_LINK)

    # Only link existing targets (components may not be found)
    set(_TO_LINK "")
    foreach(_t IN LISTS _NEED_LINK)
      if(TARGET ${_t})
        list(APPEND _TO_LINK ${_t})
      endif()
    endforeach()

    if(_TO_LINK)
      foreach(ODB_TARGET IN LISTS ODB_TARGETS)
        target_link_libraries(${ODB_TARGET} PRIVATE ${_TO_LINK})
      endforeach()
    endif()
  endif()

  # Return generated sources if requested
  if(ODB_OUT_VAR)
    set(${ODB_OUT_VAR} "${_ALL_GEN_CXX}" PARENT_SCOPE)
  endif()
endfunction()
