# This is the main entry point for defining Qt plugins.
# A CMake target is created with the given target. The TYPE parameter is needed to place the
# plugin into the correct plugins/ sub-directory.
function(qt_internal_add_plugin target)
    qt_internal_module_info(module "${target}")

    qt_internal_set_qt_known_plugins("${QT_KNOWN_PLUGINS}" "${target}")

    qt_parse_all_arguments(arg "qt_internal_add_plugin"
        "${__qt_add_plugin_optional_args};SKIP_INSTALL"
        "${__qt_add_plugin_single_args}"
        "${__qt_add_plugin_multi_args}"
        "${ARGN}"
    )

    # Put this behind a cache option for now. It's too noisy for general use
    # until most repos are updated.
    option(QT_WARN_PLUGIN_PUBLIC_KEYWORDS "Warn if a plugin specifies a PUBLIC keyword")
    if(QT_WARN_PLUGIN_PUBLIC_KEYWORDS)
        foreach(publicKeyword IN LISTS __default_public_args)
            if(NOT "${arg_${publicKeyword}}" STREQUAL "")
                string(REPLACE "PUBLIC_" "" privateKeyword "${publicKeyword}")
                message(AUTHOR_WARNING
                    "Plugins are not intended to be linked to. "
                    "They should not have any public properties, but ${target} "
                    "sets ${publicKeyword} to the following value:\n"
                    "    ${arg_${publicKeyword}}\n"
                    "Update your project to use ${privateKeyword} instead.\n")
            endif()
        endforeach()
    endif()

    qt_get_sanitized_plugin_type("${arg_TYPE}" plugin_type_escaped)

    set(output_directory_default "${QT_BUILD_DIR}/${INSTALL_PLUGINSDIR}/${arg_TYPE}")
    set(install_directory_default "${INSTALL_PLUGINSDIR}/${arg_TYPE}")

    # Derive the class name from the target name if it's not explicitly specified.
    # Don't set it for qml plugins though.
    set(plugin_class_name "")
    if (NOT "${plugin_type_escaped}" STREQUAL "qml_plugin")
        if (NOT arg_CLASS_NAME)
            set(plugin_class_name "${target}")
        else()
            set(plugin_class_name "${arg_CLASS_NAME}")
        endif()
    endif()

    qt_internal_check_directory_or_type(OUTPUT_DIRECTORY "${arg_OUTPUT_DIRECTORY}" "${arg_TYPE}"
        "${output_directory_default}" output_directory)
    if (NOT arg_SKIP_INSTALL)
        qt_internal_check_directory_or_type(INSTALL_DIRECTORY "${arg_INSTALL_DIRECTORY}" "${arg_TYPE}"
            "${install_directory_default}" install_directory)
        set(archive_install_directory ${arg_ARCHIVE_INSTALL_DIRECTORY})
        if (NOT archive_install_directory AND install_directory)
            set(archive_install_directory "${install_directory}")
        endif()
    endif()

    if(arg_STATIC OR NOT BUILD_SHARED_LIBS)
        add_library("${target}" STATIC)
    else()
        add_library("${target}" MODULE)
        if(APPLE)
            # CMake defaults to using .so extensions for loadable modules, aka plugins,
            # but Qt plugins are actually suffixed with .dylib.
            set_property(TARGET "${target}" PROPERTY SUFFIX ".dylib")
        endif()
        qt_internal_apply_win_prefix_and_suffix("${target}")
    endif()

    qt_set_common_target_properties(${target})
    qt_set_target_info_properties(${target} ${ARGN} TARGET_VERSION "${arg_VERSION}")

    # Make sure the Qt6 plugin library names are like they were in Qt5 qmake land.
    # Whereas the Qt6 CMake target names are like the Qt5 CMake target names.
    set(output_name "${target}")
    if(arg_OUTPUT_NAME)
        set(output_name "${arg_OUTPUT_NAME}")
    endif()
    set_property(TARGET "${target}" PROPERTY OUTPUT_NAME "${output_name}${QT_LIBINFIX}")

    # Add a custom target with the Qt5 qmake name for a more user friendly ninja experience.
    if(arg_OUTPUT_NAME AND NOT TARGET "${output_name}")
        # But don't create such a target if it would just differ in case from "${target}"
        # and we're not using Ninja. See https://gitlab.kitware.com/cmake/cmake/-/issues/21915
        string(TOUPPER "${output_name}" uc_output_name)
        string(TOUPPER "${target}" uc_target)
        if(NOT uc_output_name STREQUAL uc_target OR CMAKE_GENERATOR MATCHES "^Ninja")
            add_custom_target("${output_name}")
            add_dependencies("${output_name}" "${target}")
        endif()
    endif()

    if (ANDROID)
        qt_android_apply_arch_suffix("${target}")
        set_target_properties(${target}
            PROPERTIES
            LIBRARY_OUTPUT_NAME "plugins_${arg_TYPE}_${output_name}"
        )
    endif()
    qt_internal_add_target_aliases("${target}")
    qt_skip_warnings_are_errors_when_repo_unclean("${target}")
    _qt_internal_apply_strict_cpp("${target}")

    # Disable linking of plugins against other plugins during static regular and
    # super builds. The latter causes cyclic dependencies otherwise.
    _qt_internal_disable_static_default_plugins("${target}")

    set_target_properties("${target}" PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${output_directory}"
        RUNTIME_OUTPUT_DIRECTORY "${output_directory}"
        ARCHIVE_OUTPUT_DIRECTORY "${output_directory}"
        QT_PLUGIN_TYPE "${plugin_type_escaped}"
        # Save the non-sanitized plugin type values for qmake consumption via .pri files.
        QT_QMAKE_PLUGIN_TYPE "${arg_TYPE}"
        QT_PLUGIN_CLASS_NAME "${plugin_class_name}")
        qt_handle_multi_config_output_dirs("${target}")

    qt_internal_library_deprecation_level(deprecation_define)

    qt_autogen_tools_initial_setup(${target})

    set(static_plugin_define "")
    if (arg_STATIC OR NOT QT_BUILD_SHARED_LIBS)
        set(static_plugin_define "QT_STATICPLUGIN")
    endif()

    # Save the Qt module in the plug-in's properties
    if(NOT plugin_type_escaped STREQUAL "qml_plugin")
        qt_internal_get_module_for_plugin("${target}" "${plugin_type_escaped}" qt_module)
        set_target_properties("${target}" PROPERTIES QT_MODULE "${qt_module}")
        set(plugin_install_package_suffix "${qt_module}")
    endif()

    # Add the plug-in to the list of plug-ins of this module
    if(TARGET "${qt_module}")
        set_property(TARGET "${qt_module}" APPEND PROPERTY QT_PLUGINS "${target}")
        get_target_property(module_source_dir ${qt_module} SOURCE_DIR)
        get_directory_property(module_project_name
            DIRECTORY ${module_source_dir}
            DEFINITION PROJECT_NAME
        )
        if(module_project_name STREQUAL PROJECT_NAME)
            set_property(TARGET ${qt_module} APPEND PROPERTY QT_REPO_PLUGINS "${target}")
            set_property(TARGET ${qt_module} APPEND PROPERTY QT_REPO_PLUGIN_CLASS_NAMES
                "$<TARGET_PROPERTY:${target},QT_PLUGIN_CLASS_NAME>"
            )
        endif()
    endif()

    # Change the configuration file install location for qml plugins into the Qml package location.
    if(plugin_type_escaped STREQUAL "qml_plugin" AND TARGET "${INSTALL_CMAKE_NAMESPACE}::Qml")
        set(plugin_install_package_suffix "Qml/QmlPlugins")
    endif()

    # Save the install package suffix as a property, so that the Dependencies file is placed
    # in the current location.
    if(plugin_install_package_suffix)
        set_target_properties("${target}" PROPERTIES
                              _qt_plugin_install_package_suffix "${plugin_install_package_suffix}")
    endif()

    # The generic plugins should be enabled by default.
    # But platform plugins should always be disabled by default, and only one is enabled
    # based on the platform (condition specified in arg_DEFAULT_IF).
    if(plugin_type_escaped STREQUAL "platforms")
        set(_default_plugin 0)
    else()
        set(_default_plugin 1)
    endif()

    if (DEFINED arg_DEFAULT_IF)
      if (NOT ${arg_DEFAULT_IF})
          set(_default_plugin 0)
      else()
          set(_default_plugin 1)
      endif()
    endif()

    add_dependencies(qt_plugins "${target}")
    if(arg_TYPE STREQUAL "platforms")
        add_dependencies(qpa_plugins "${target}")

        if(_default_plugin)
            add_dependencies(qpa_default_plugins "${target}")
        endif()
    endif()

    set_property(TARGET "${target}" PROPERTY QT_DEFAULT_PLUGIN "${_default_plugin}")
    set_property(TARGET "${target}" APPEND PROPERTY EXPORT_PROPERTIES "QT_PLUGIN_CLASS_NAME;QT_PLUGIN_TYPE;QT_MODULE;QT_DEFAULT_PLUGIN")

    set(private_includes
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
         # For the syncqt headers
        "$<BUILD_INTERFACE:${module_repo_include_dir}>"
         ${arg_INCLUDE_DIRECTORIES}
    )

    set(public_includes
        ${arg_PUBLIC_INCLUDE_DIRECTORIES}
    )

    qt_internal_extend_target("${target}"
        SOURCES ${arg_SOURCES}
        INCLUDE_DIRECTORIES
            ${private_includes}
        PUBLIC_INCLUDE_DIRECTORIES
            ${public_includes}
        LIBRARIES ${arg_LIBRARIES} Qt::PlatformPluginInternal
        PUBLIC_LIBRARIES ${arg_PUBLIC_LIBRARIES}
        DEFINES
            ${arg_DEFINES}
            QT_DEPRECATED_WARNINGS
            ${deprecation_define}
            "${static_plugin_define}"
            QT_PLUGIN
        PUBLIC_DEFINES
            ${arg_PUBLIC_DEFINES}
        FEATURE_DEPENDENCIES ${arg_FEATURE_DEPENDENCIES}
        DBUS_ADAPTOR_SOURCES "${arg_DBUS_ADAPTOR_SOURCES}"
        DBUS_ADAPTOR_FLAGS "${arg_DBUS_ADAPTOR_FLAGS}"
        DBUS_INTERFACE_SOURCES "${arg_DBUS_INTERFACE_SOURCES}"
        DBUS_INTERFACE_FLAGS "${arg_DBUS_INTERFACE_FLAGS}"
        COMPILE_OPTIONS ${arg_COMPILE_OPTIONS}
        PUBLIC_COMPILE_OPTIONS ${arg_PUBLIC_COMPILE_OPTIONS}
        LINK_OPTIONS ${arg_LINK_OPTIONS}
        PUBLIC_LINK_OPTIONS ${arg_PUBLIC_LINK_OPTIONS}
        MOC_OPTIONS ${arg_MOC_OPTIONS}
        ENABLE_AUTOGEN_TOOLS ${arg_ENABLE_AUTOGEN_TOOLS}
        DISABLE_AUTOGEN_TOOLS ${arg_DISABLE_AUTOGEN_TOOLS}
    )

    qt_internal_set_exceptions_flags("${target}" ${arg_EXCEPTIONS})


    set(qt_libs_private "")
    qt_internal_get_qt_all_known_modules(known_modules)
    foreach(it ${known_modules})
        list(FIND arg_LIBRARIES "Qt::${it}Private" pos)
        if(pos GREATER -1)
            list(APPEND qt_libs_private "Qt::${it}Private")
        endif()
    endforeach()

    qt_register_target_dependencies("${target}" "${arg_PUBLIC_LIBRARIES}" "${qt_libs_private}")
    if (NOT BUILD_SHARED_LIBS)
        qt_generate_plugin_pri_file("${target}" pri_file)
    endif()

    if (NOT arg_SKIP_INSTALL)
        # Handle creation of cmake files for consumers of find_package().
        # If we are part of a Qt module, the plugin cmake files are installed as part of that
        # module.
        # For qml plugins, they are all installed into the QtQml package location for automatic
        # discovery.
        if(plugin_install_package_suffix)
            set(path_suffix "${INSTALL_CMAKE_NAMESPACE}${plugin_install_package_suffix}")
        else()
            set(path_suffix "${INSTALL_CMAKE_NAMESPACE}${target}")
        endif()

        qt_path_join(config_build_dir ${QT_CONFIG_BUILD_DIR} ${path_suffix})
        qt_path_join(config_install_dir ${QT_CONFIG_INSTALL_DIR} ${path_suffix})

        qt_internal_export_additional_targets_file(
            TARGETS ${target}
            EXPORT_NAME_PREFIX ${INSTALL_CMAKE_NAMESPACE}${target}
            CONFIG_INSTALL_DIR "${config_install_dir}")

        qt_internal_get_min_new_policy_cmake_version(min_new_policy_version)
        qt_internal_get_max_new_policy_cmake_version(max_new_policy_version)
        configure_package_config_file(
            "${QT_CMAKE_DIR}/QtPluginConfig.cmake.in"
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}Config.cmake"
            INSTALL_DESTINATION "${config_install_dir}"
        )
        write_basic_package_version_file(
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}ConfigVersion.cmake"
            VERSION ${PROJECT_VERSION}
            COMPATIBILITY AnyNewerVersion
        )

        qt_install(FILES
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}Config.cmake"
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}ConfigVersion.cmake"
            DESTINATION "${config_install_dir}"
            COMPONENT Devel
        )
        if(pri_file)
            qt_install(FILES "${pri_file}" DESTINATION "${INSTALL_MKSPECSDIR}/modules")
        endif()

        # Make the export name of plugins be consistent with modules, so that
        # qt_add_resource adds its additional targets to the same export set in a static Qt build.
        set(export_name "${INSTALL_CMAKE_NAMESPACE}${target}Targets")
        qt_install(TARGETS "${target}"
                   EXPORT ${export_name}
                   RUNTIME DESTINATION "${install_directory}"
                   LIBRARY DESTINATION "${install_directory}"
                   ARCHIVE DESTINATION "${archive_install_directory}"
        )
        qt_install(EXPORT ${export_name}
                   NAMESPACE ${QT_CMAKE_EXPORT_NAMESPACE}::
                   DESTINATION "${config_install_dir}"
        )
        qt_apply_rpaths(TARGET "${target}" INSTALL_PATH "${install_directory}" RELATIVE_RPATH)
    endif()

    if (NOT arg_ALLOW_UNDEFINED_SYMBOLS)
        ### fixme: cmake is missing a built-in variable for this. We want to apply it only to
        # modules and plugins that belong to Qt.
        qt_internal_add_link_flags_no_undefined("${target}")
    endif()

    qt_internal_add_linker_version_script(${target})
    qt_add_list_file_finalizer(qt_finalize_plugin ${target} "${install_directory}")

    qt_enable_separate_debug_info(${target} "${install_directory}")
    qt_internal_install_pdb_files(${target} "${install_directory}")
endfunction()

function(qt_finalize_plugin target install_directory)
    if(WIN32 AND BUILD_SHARED_LIBS)
        _qt_internal_generate_win32_rc_file("${target}")
    endif()

    # Generate .prl files for plugins of static Qt builds.
    if(NOT BUILD_SHARED_LIBS)
        qt_generate_prl_file(${target} "${install_directory}")
    endif()
endfunction()

function(qt_get_sanitized_plugin_type plugin_type out_var)
    # Used to handle some edge cases such as platforms/darwin
    string(REGEX REPLACE "[-/]" "_" plugin_type "${plugin_type}")
    set("${out_var}" "${plugin_type}" PARENT_SCOPE)
endfunction()

# Utility function to find the module to which a plug-in belongs.
function(qt_internal_get_module_for_plugin target target_type out_var)
    qt_internal_get_qt_all_known_modules(known_modules)

    qt_get_sanitized_plugin_type("${target_type}" target_type)
    foreach(qt_module ${known_modules})
        get_target_property(module_type "${QT_CMAKE_EXPORT_NAMESPACE}::${qt_module}" TYPE)
        # Assuming interface libraries can't have plugins. Otherwise we'll need to fix the property
        # name, because the current one would be invalid for interface libraries.
        if(module_type STREQUAL "INTERFACE_LIBRARY")
            continue()
        endif()

        get_target_property(plugin_types
                           "${QT_CMAKE_EXPORT_NAMESPACE}::${qt_module}"
                            MODULE_PLUGIN_TYPES)
        if(plugin_types AND target_type IN_LIST plugin_types)
            set("${out_var}" "${qt_module}" PARENT_SCOPE)
            return()
        endif()
    endforeach()
    message(FATAL_ERROR "The plug-in '${target}' does not belong to any Qt module.")
endfunction()
