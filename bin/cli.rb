require 'thor'

# Special handler to prevent Thor from barfing on unrecognized CLI arguments (i.e. Rake tasks)
module PermissiveCLI
  def self.extended(base)
    super
    base.check_unknown_options!
  end

  def start(args, config={})
    config[:shell] ||= Thor::Base.shell.new
    dispatch(nil, args, nil, config)
  rescue Thor::UndefinedCommandError
    # Eat unhandled command errors
    #  - No error message
    #  - No `exit()`
    #  - Re-raise to allow Rake task handling
    raise
  end
end

module CeedlingTasks
  class CLI < Thor
    include Thor::Actions
    extend PermissiveCLI

    # Ensure we bail out with non-zero exit code if the command line is wrong
    def self.exit_on_failure?() true end

    # Allow `build` to be omitted in command line
    default_task :build

    # Intercept construction to extract configuration and injected dependencies
    def initialize(args, config, options)
      super(args, config, options)

      @app_cfg = options[:app_cfg]
      @handler = options[:objects][:cli_handler]
    end


    # Override Thor help to list Rake tasks as well
    desc "help [COMMAND]", "Describe available commands and list build operations"
    def help(command=nil)
      # Call application help with block to execute Thor's built-in help after Ceedling loads
      @handler.app_help( @app_cfg, command ) { |command| super(command) }
    end


    desc "new PROJECT_NAME", "Create a new project"
    method_option :docs, :type => :boolean, :default => false, :desc => "Add docs in project vendor directory"
    method_option :local, :type => :boolean, :default => false, :desc => "Create a copy of Ceedling in the project vendor directory"
    method_option :gitignore, :type => :boolean, :default => false, :desc => "Create a gitignore file for ignoring ceedling generated files"
    method_option :no_configs, :type => :boolean, :default => false, :desc => "Don't install starter configuration files"
    method_option :noconfigs, :type => :boolean, :default => false

    #deprecated:
    method_option :no_docs, :type => :boolean, :default => false
    method_option :nodocs, :type => :boolean, :default => false
    method_option :as_gem, :type => :boolean, :default => false
    method_option :asgem, :type => :boolean, :default => false
    method_option :with_ignore, :type => :boolean, :default => false
    method_option :withignore, :type => :boolean, :default => false
    def new(name, silent = false)
      @handler.copy_assets_and_create_structure(name, silent, false, options)
    end


    desc "upgrade PROJECT_NAME", "Upgrade ceedling for a project (not req'd if gem used)"
    def upgrade(name, silent = false)
      as_local = true
      yaml_path = File.join(name, "project.yml")
      begin
        require File.join(CEEDLING_ROOT,"lib","ceedling","yaml_wrapper.rb")
        as_local = (YamlWrapper.new.load(yaml_path)[:project][:which_ceedling] != 'gem')
      rescue
        raise "ERROR: Could not find valid project file '#{yaml_path}'"
      end
      found_docs = File.exist?( File.join(name, "docs", "CeedlingPacket.md") )
      @handler.copy_assets_and_create_structure(name, silent, true, {:upgrade => true, :no_configs => true, :local => as_local, :docs => found_docs})
    end


    desc "build TASKS", "Run build tasks"
    method_option :project, :type => :string, :default => nil, :aliases => ['-p']
    method_option :verbosity, :enum => ['silent', 'errors', 'warnings', 'normal', 'obnoxious', 'debug'], :aliases => ['-v']
    # method_option :num, :type => :numeric, :enum => [0, 1, 2, 3, 4, 5], :aliases => ['-n']
    method_option :mixin, :type => :string, :default => [], :repeatable => true, :aliases => ['-m']
    method_option :log, :type => :boolean, :default => false, :aliases => ['-l']
    method_option :logfile, :type => :string, :default => ''
    method_option :test_case, :type => :string, :default => ''
    method_option :exclude_test_case, :type => :string, :default => ''
    def build(*tasks)
      @handler.app_exec( @app_cfg, options, tasks )
    end


    desc "dumpconfig FILEPATH [SECTIONS]", "Process project configuration and dump to to a YAML file"
    method_option :project, :type => :string, :default => nil, :aliases => ['-p']
    method_option :mixin, :type => :string, :default => [], :repeatable => true, :aliases => ['-m']
    def dumpconfig(filepath, *sections)
      @handler.dumpconfig( @app_cfg, options, filepath, sections )
    end


    desc "tasks", "List all build operations"
    method_option :project, :type => :string, :default => nil, :aliases => ['-p']
    method_option :mixin, :type => :string, :default => [], :repeatable => true, :aliases => ['-m']
    def tasks()
      @handler.rake_tasks( app_cfg: @app_cfg, project: options[:project], mixins: options[:mixin] )
    end


    desc "examples", "list available example projects"
    def examples()
      puts "Available sample projects:"
      FileUtils.cd(File.join(CEEDLING_ROOT, "examples")) do
        Dir["*"].each {|proj| puts "  #{proj}"}
      end
    end

    desc "example PROJ_NAME [DEST]", "new specified example project (in DEST, if specified)"
    def example(proj_name, dest=nil)
      if dest.nil? then dest = proj_name end

      copy_assets_and_create_structure(dest, true, false, {:local=>true, :docs=>true})

      dest_src      = File.join(dest,'src')
      dest_test     = File.join(dest,'test')
      dest_project  = File.join(dest,'project.yml')

      directory "examples/#{proj_name}/src",         dest_src
      directory "examples/#{proj_name}/test",        dest_test
      remove_file dest_project
      copy_file "examples/#{proj_name}/project.yml", dest_project

      puts "\n"
      puts "Example project '#{proj_name}' created!"
      puts " - Tool documentation is located in vendor/ceedling/docs"
      puts " - Execute 'ceedling help' to view available test & build tasks"
      puts ''
    end


    desc "version", "Version details for Ceedling components"
    def version()
      @handler.version()
    end

  end
end
