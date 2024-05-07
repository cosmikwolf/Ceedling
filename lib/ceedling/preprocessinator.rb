# =========================================================================
#   Ceedling - Test-Centered Build System for C
#   ThrowTheSwitch.org
#   Copyright (c) 2010-24 Mike Karlesky, Mark VanderVoord, & Greg Williams
#   SPDX-License-Identifier: MIT
# =========================================================================

class Preprocessinator

  constructor :preprocessinator_includes_handler,
              :preprocessinator_file_handler,
              :task_invoker,
              :file_finder,
              :file_path_utils,
              :file_wrapper,
              :yaml_wrapper,
              :plugin_manager,
              :configurator,
              :test_context_extractor,
              :loginator,
              :reportinator,
              :rake_wrapper


  def setup
    # Aliases
    @includes_handler = @preprocessinator_includes_handler
    @file_handler = @preprocessinator_file_handler
  end

  def extract_test_build_directives(filepath:)
    # Parse file in Ruby to extract build directives
    msg = @reportinator.generate_progress( "Parsing #{File.basename(filepath)}" )
    @loginator.log( msg, Verbosity::NORMAL )
    @test_context_extractor.collect_build_directives( filepath )
  end

  def extract_testing_context(filepath:, test:, flags:, include_paths:, defines:)
    if (not @configurator.project_use_test_preprocessor)
      # Parse file in Ruby to extract testing details (e.g. header files, mocks, etc.)
      msg = @reportinator.generate_progress( "Parsing & processing #include statements within #{File.basename(filepath)}" )
      @loginator.log( msg, Verbosity::NORMAL )
      @test_context_extractor.collect_includes( filepath )
    else
      # Run test file through preprocessor to parse out include statements and then collect header files, mocks, etc.
      arg_hash = {
        filepath:      filepath,
        test:          test,
        flags:         flags,
        include_paths: include_paths,
        defines:       defines
      }

      includes = preprocess_includes(**arg_hash)

      msg = @reportinator.generate_progress( "Processing #include statements for #{File.basename(filepath)}" )
      @loginator.log( msg, Verbosity::NORMAL )

      @test_context_extractor.ingest_includes( filepath, includes )
    end
  end

  def preprocess_mockable_header_file(filepath:, test:, flags:, include_paths:, defines:)
    preprocessed_filepath = @file_path_utils.form_preprocessed_file_filepath( filepath, test )

    plugin_arg_hash = {
      header_file:              filepath,
      preprocessed_header_file: preprocessed_filepath,
      test:                     test,
      flags:                    flags,
      include_paths:            include_paths,
      defines:                  defines      
    }

    # Trigger pre_mock_preprocessing plugin hook
    @plugin_manager.pre_mock_preprocess( plugin_arg_hash )

    arg_hash = {
      filepath:       filepath,
      test:           test,
      flags:          flags,
      include_paths:  include_paths,
      defines:        defines      
    }

    # Extract shallow includes & print status message    
    includes = preprocess_file_common( **arg_hash )

    arg_hash = {
      source_filepath:       filepath,
      preprocessed_filepath: preprocessed_filepath,
      includes:              includes,
      flags:                 flags,
      include_paths:         include_paths,
      defines:               defines      
    }

    # Run file through preprocessor & further process result
    plugin_arg_hash[:shell_result] = @file_handler.preprocess_header_file( **arg_hash )

    # Trigger post_mock_preprocessing plugin hook
    @plugin_manager.post_mock_preprocess( plugin_arg_hash )

    return preprocessed_filepath
  end

  def preprocess_test_file(filepath:, test:, flags:, include_paths:, defines:)
    preprocessed_filepath = @file_path_utils.form_preprocessed_file_filepath( filepath, test )

    plugin_arg_hash = {
      test_file:              filepath,
      preprocessed_test_file: preprocessed_filepath,
      test:                   test,
      flags:                  flags,
      include_paths:          include_paths,
      defines:                defines      
    }

    # Trigger pre_mock_preprocessing plugin hook
    @plugin_manager.pre_test_preprocess( plugin_arg_hash )

    arg_hash = {
      filepath:      filepath,
      test:          test,
      flags:         flags,
      include_paths: include_paths,
      defines:       defines      
    }

    # Extract shallow includes & print status message
    includes = preprocess_file_common( **arg_hash )

    arg_hash = {
      source_filepath:       filepath,
      preprocessed_filepath: preprocessed_filepath,
      includes:              includes,
      flags:                 flags,
      include_paths:         include_paths,
      defines:               defines      
    }

    # Run file through preprocessor & further process result
    plugin_arg_hash[:shell_result] = @file_handler.preprocess_test_file( **arg_hash )

    # Trigger pre_mock_preprocessing plugin hook
    @plugin_manager.post_test_preprocess( plugin_arg_hash )

    return preprocessed_filepath
  end

  def preprocess_file_directives(filepath)
    @includes_handler.invoke_shallow_includes_list( filepath )
    @file_handler.preprocess_file_directives( filepath,
      @yaml_wrapper.load( @file_path_utils.form_preprocessed_includes_list_filepath( filepath ) ) )
  end

  ### Private ###
  private

  def preprocess_file_common(filepath:, test:, flags:, include_paths:, defines:)
    msg = @reportinator.generate_module_progress(
      operation: "Preprocessing",
      module_name: test,
      filename: File.basename(filepath)
    )

    @loginator.log( msg, Verbosity::NORMAL )

    # Extract includes
    includes = preprocess_includes(
      filepath:      filepath,
      test:          test,
      flags:         flags,
      include_paths: include_paths,
      defines:       defines) 

    return includes
  end

  def preprocess_includes(filepath:, test:, flags:, include_paths:, defines:)
    includes_list_filepath = @file_path_utils.form_preprocessed_includes_list_filepath( filepath, test )

    includes = []
    if @file_wrapper.newer?(includes_list_filepath, filepath)
      msg = @reportinator.generate_module_progress(
        operation: "Loading #include statement listing file for",
        module_name: test,
        filename: File.basename(filepath)
        )
      @loginator.log( msg, Verbosity::NORMAL )
      includes = @yaml_wrapper.load( includes_list_filepath )
    else
      includes = @includes_handler.extract_includes(
        filepath:      filepath,
        test:          test,
        flags:         flags,
        include_paths: include_paths,
        defines:       defines
        )
      
      @includes_handler.write_includes_list( includes_list_filepath, includes )
    end

    return includes
  end

end
