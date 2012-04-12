require 'rubygems/installer_test_case'

class TestGemInstaller < Gem::InstallerTestCase

  def setup
    super

    if __name__ =~ /^test_install(_|$)/ then
      FileUtils.rm_r @spec.gem_dir
      FileUtils.rm_r @user_spec.gem_dir
    end

    @config = Gem.configuration
  end

  def teardown
    super

    Gem.configuration = @config
  end

  def test_app_script_text
    util_make_exec @spec, ''

    expected = <<-EOF
#!#{Gem.ruby}
#
# This file was generated by RubyGems.
#
# The application 'a' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = \">= 0\"

if ARGV.first
  str = ARGV.first
  str = str.dup.force_encoding("BINARY") if str.respond_to? :force_encoding
  if str =~ /\\A_(.*)_\\z/
    version = $1
    ARGV.shift
  end
end

gem 'a', version
load Gem.bin_path('a', 'executable', version)
    EOF

    wrapper = @installer.app_script_text 'executable'
    assert_equal expected, wrapper
  end

  def test_build_extensions_none
    use_ui @ui do
      @installer.build_extensions
    end

    assert_equal '', @ui.output
    assert_equal '', @ui.error

    refute File.exist?('gem_make.out')
  end

  def test_build_extensions_extconf_bad
    @installer.spec = @spec
    @spec.extensions << 'extconf.rb'

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/\AERROR: Failed to build gem native extension.$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    gem_make_out = File.join @gemhome, 'gems', @spec.full_name, 'gem_make.out'

    assert_match %r%#{Regexp.escape Gem.ruby} extconf\.rb%,
                 File.read(gem_make_out)
    assert_match %r%#{Regexp.escape Gem.ruby}: No such file%,
                 File.read(gem_make_out)
  end

  def test_build_extensions_unsupported
    @installer.spec = @spec
    FileUtils.mkdir_p @spec.gem_dir
    gem_make_out = File.join @spec.gem_dir, 'gem_make.out'
    @spec.extensions << nil

    e = assert_raises Gem::Installer::ExtensionBuildError do
      use_ui @ui do
        @installer.build_extensions
      end
    end

    assert_match(/^\s*No builder for extension ''$/, e.message)

    assert_equal "Building native extensions.  This could take a while...\n",
                 @ui.output
    assert_equal '', @ui.error

    assert_equal "No builder for extension ''\n", File.read(gem_make_out)
  ensure
    FileUtils.rm_f gem_make_out
  end

  def test_build_extensions_with_build_args
    args = ["--aa", "--bb"]
    @installer.build_args = args
    @installer.spec = @spec
    @spec.extensions << 'extconf.rb'

    File.open File.join(@spec.gem_dir, "extconf.rb"), "w" do |f|
      f.write <<-'RUBY'
        puts "IN EXTCONF"
        File.open 'extconf_args', 'w' do |f|
          f.puts ARGV.inspect
        end

        File.open 'Makefile', 'w' do |f|
          f.puts "default:\n\techo built"
          f.puts "install:\n\techo installed"
        end
      RUBY
    end

    use_ui @ui do
      @installer.build_extensions
    end

    path = File.join @spec.gem_dir, "extconf_args"

    assert_equal args.inspect, File.read(path).strip
  end

  def test_check_executable_overwrite
    @installer.generate_bin

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    @installer.gem_dir = util_gem_dir @spec
    @installer.wrappers = true
    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert File.exist? installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_check_executable_overwrite_default_bin_dir
    if defined?(RUBY_FRAMEWORK_VERSION)
      orig_RUBY_FRAMEWORK_VERSION = RUBY_FRAMEWORK_VERSION
      Object.send :remove_const, :RUBY_FRAMEWORK_VERSION
    end
    orig_bindir = Gem::ConfigMap[:bindir]
    Gem::ConfigMap[:bindir] = Gem.bindir

    util_conflict_executable false

    ui = Gem::MockGemUi.new "n\n"
    use_ui ui do
      e = assert_raises Gem::InstallError do
        @installer.generate_bin
      end

      conflicted = File.join @gemhome, 'bin', 'executable'
      assert_equal "\"executable\" from a conflicts with #{conflicted}",
                   e.message
    end
  ensure
    Object.const_set :RUBY_FRAMEWORK_VERSION, orig_RUBY_FRAMEWORK_VERSION if
      orig_RUBY_FRAMEWORK_VERSION
    Gem::ConfigMap[:bindir] = orig_bindir
  end

  def test_check_executable_overwrite_other_gem
    util_conflict_executable true

    ui = Gem::MockGemUi.new "n\n"

    use_ui ui do
      e = assert_raises Gem::InstallError do
        @installer.generate_bin
      end

      assert_equal '"executable" from a conflicts with installed executable from conflict',
                   e.message
    end
  end

  def test_check_executable_overwrite_other_gem_force
    util_conflict_executable true
    @installer.wrappers = true
    @installer.force = true

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert File.exist? installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_check_executable_overwrite_other_non_gem
    util_conflict_executable false
    @installer.wrappers = true

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert File.exist? installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_ensure_dependency
    quick_spec 'a'

    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.ensure_dependency(@spec, dep)

    dep = Gem::Dependency.new 'b', '> 2'
    e = assert_raises Gem::InstallError do
      @installer.ensure_dependency @spec, dep
    end

    assert_equal 'a requires b (> 2)', e.message
  end

  def test_extract_files
    @installer.extract_files

    assert_path_exists File.join util_gem_dir, 'bin/executable'
  end

  def test_generate_bin_bindir
    @installer.wrappers = true

    @spec.executables = %w[executable]
    @spec.bindir = '.'

    exec_file = @installer.formatted_program_filename 'executable'
    exec_path = File.join util_gem_dir(@spec), exec_file
    File.open exec_path, 'w' do |f|
      f.puts '#!/usr/bin/ruby'
    end

    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_bindir_with_user_install_warning
    bin_dir = Gem.win_platform? ? File.expand_path(ENV["WINDIR"]) : "/usr/bin"

    options = {
      :bin_dir => bin_dir,
      :install_dir => "/non/existant"
    }

    inst = Gem::Installer.new '', options

    Gem::Installer.path_warning = false

    use_ui @ui do
      inst.check_that_user_bin_dir_is_in_path
    end

    assert_equal "", @ui.error
  end

  def test_generate_bin_script
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert File.directory? util_inst_bindir
    installed_exec = File.join util_inst_bindir, 'executable'
    assert File.exist? installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_format
    @installer.format_executable = true
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'foo-executable-bar'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_format_disabled
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.exist?(installed_exec)
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_install_dir
    @installer.wrappers = true

    gem_dir = File.join("#{@gemhome}2", "gems", @spec.full_name)
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "#!/bin/ruby"
    end

    @installer.gem_home = "#{@gemhome}2"
    @installer.gem_dir = gem_dir
    @installer.bin_dir = File.join "#{@gemhome}2", 'bin'

    @installer.generate_bin

    installed_exec = File.join("#{@gemhome}2", "bin", 'executable')
    assert File.exist? installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_no_execs
    util_execless

    @installer.wrappers = true
    @installer.generate_bin

    refute File.exist?(util_inst_bindir), 'bin dir was created when not needed'
  end

  def test_generate_bin_script_no_perms
    @installer.wrappers = true
    util_make_exec

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_script_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_script_no_shebang
    @installer.wrappers = true
    @spec.executables = %w[executable]

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "blah blah blah"
    end

    @installer.generate_bin

    installed_exec = File.join @gemhome, 'bin', 'executable'
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
    # HACK some gems don't have #! in their executables, restore 2008/06
    #assert_no_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_wrappers
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir
    installed_exec = File.join(util_inst_bindir, 'executable')

    real_exec = File.join util_gem_dir, 'bin', 'executable'

    # fake --no-wrappers for previous install
    unless Gem.win_platform? then
      FileUtils.mkdir_p File.dirname(installed_exec)
      FileUtils.ln_s real_exec, installed_exec
    end

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    assert_equal true, File.exist?(installed_exec)
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    assert_match %r|generated by RubyGems|, File.read(installed_exec)

    refute_match %r|generated by RubyGems|, File.read(real_exec),
                 'real executable overwritten'
  end

  def test_generate_bin_symlink
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlink_no_execs
    util_execless

    @installer.wrappers = false
    @installer.generate_bin

    refute File.exist?(util_inst_bindir)
  end

  def test_generate_bin_symlink_no_perms
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_symlink_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_symlink_update_newer
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    @installer.gem_dir = util_gem_dir @spec
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(@spec.bin_file('executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    one = @spec.dup
    one.version = 1
    @installer.gem_dir = util_gem_dir one
    @installer.spec = spec

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    expected = File.join util_gem_dir, 'bin', 'executable'
    assert_equal(expected,
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlink_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert File.exist? installed_exec

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end
    util_make_exec

    util_installer @spec, @gemhome
    @installer.wrappers = false
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal(@spec.bin_file('executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_win32
    old_win_platform = Gem.win_platform?
    Gem.win_platform = true
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    use_ui @ui do
      @installer.generate_bin
    end

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal true, File.exist?(installed_exec)

    assert_match(/Unable to use symlinks on Windows, installing wrapper/i,
                 @ui.error)

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    Gem.win_platform = old_win_platform
  end

  def test_generate_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec

    @installer.generate_bin

    default_shebang = Gem.ruby
    shebang_line = open("#{@gemhome}/bin/executable") { |f| f.readlines.first }
    assert_match(/\A#!/, shebang_line)
    assert_match(/#{default_shebang}/, shebang_line)
  end

  def test_initialize
    spec = quick_spec 'a' do |s| s.platform = Gem::Platform.new 'mswin32' end
    gem = File.join @tempdir, spec.file_name

    Dir.mkdir util_inst_bindir
    util_build_gem spec
    FileUtils.mv spec.cache_file, @tempdir

    installer = Gem::Installer.new gem

    assert_equal File.join(@gemhome, 'gems', spec.full_name), installer.gem_dir
  end

  def test_install
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    gemdir     = File.join @gemhome, 'gems', @spec.full_name
    cache_file = File.join @gemhome, 'cache', @spec.file_name
    stub_exe   = File.join @gemhome, 'bin', 'executable'
    rakefile   = File.join gemdir, 'ext', 'a', 'Rakefile'

    Gem.pre_install do |installer|
      refute File.exist?(cache_file), 'cache file must not exist yet'
      true
    end

    Gem.post_build do |installer|
      assert File.exist?(gemdir), 'gem install dir must exist'
      assert File.exist?(rakefile), 'gem executable must exist'
      refute File.exist?(stub_exe), 'gem executable must not exist'
      true
    end

    Gem.post_install do |installer|
      assert File.exist?(cache_file), 'cache file must exist'
    end

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    assert_equal @spec, @newspec
    assert File.exist? gemdir
    assert File.exist?(stub_exe), 'gem executable must exist'

    exe = File.join gemdir, 'bin', 'executable'
    assert File.exist? exe

    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?

    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist? rakefile

    spec_file = File.join(@gemhome, 'specifications', @spec.spec_name)

    assert_equal spec_file, @newspec.loaded_from
    assert File.exist?(spec_file)

    assert_same @installer, @post_build_hook_arg
    assert_same @installer, @post_install_hook_arg
    assert_same @installer, @pre_install_hook_arg
  end

  def test_install_creates_working_binstub
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    gemdir = File.join @gemhome, 'gems', @spec.full_name

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join gemdir, 'bin', 'executable'

    e = assert_raises RuntimeError do
      instance_eval File.read(exe)
    end

    assert_match(/ran executable/, e.message)
  end

  def test_install_creates_binstub_that_understand_version
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join @gemhome, 'bin', 'executable'

    ARGV.unshift "_3.0_"

    begin
      Gem::Specification.reset

      e = assert_raises Gem::LoadError do
        instance_eval File.read(exe)
      end
    ensure
      ARGV.shift if ARGV.first == "_3.0_"
    end

    assert_match(/\(= 3\.0\)/, e.message)
  end

  def test_install_creates_binstub_that_dont_trust_encoding
    skip unless "".respond_to?(:force_encoding)

    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join @gemhome, 'bin', 'executable'

    ARGV.unshift "\xE4pfel".force_encoding("UTF-8")

    begin
      Gem::Specification.reset

      e = assert_raises RuntimeError do
        instance_eval File.read(exe)
      end
    ensure
      ARGV.shift if ARGV.first == "\xE4pfel"
    end

    assert_match(/ran executable/, e.message)
  end

  def test_install_with_no_prior_files
    Dir.mkdir util_inst_bindir
    util_clear_gems

    util_setup_gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    gemdir = File.join(@gemhome, 'gems', @spec.full_name)
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    util_setup_gem
    # Morph spec to have lib/other.rb instead of code.rb and recreate
    @spec.files = File.join('lib', 'other.rb')
    Dir.chdir @tempdir do
      File.open File.join('lib', 'other.rb'), 'w' do |f| f.puts '1' end
      use_ui ui do
        FileUtils.rm @gem
        Gem::Package.build @spec
      end
    end
    @installer = Gem::Installer.new @gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    assert File.exist?(File.join(gemdir, 'lib', 'other.rb'))
    refute(File.exist?(File.join(gemdir, 'lib', 'code.rb')),
           "code.rb from prior install of same gem shouldn't remain here")
  end

  def test_install_check_dependencies
    @spec.add_dependency 'b', '> 5'
    util_setup_gem

    use_ui @ui do
      assert_raises Gem::InstallError do
        @installer.install
      end
    end
  end

  def test_install_check_dependencies_install_dir
    gemhome2 = "#{@gemhome}2"
    @spec.add_dependency 'd'

    quick_gem 'd', 2

    FileUtils.mv @gemhome, gemhome2

    # Don't leak any already activated gems into the installer, require
    # that it work everything out on it's own.
    Gem::Specification.reset

    util_setup_gem

    @installer = Gem::Installer.new @gem, :install_dir => gemhome2

    gem_home = Gem.dir

    build_rake_in do
      use_ui @ui do
        @installer.install
      end
    end

    assert File.exist?(File.join(gemhome2, 'gems', @spec.full_name))
    assert_equal gem_home, Gem.dir
  end

  def test_install_force
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required, :force => true
      installer.install
    end

    gem_dir = File.join(@gemhome, 'gems', 'old_ruby_required-1')
    assert File.exist?(gem_dir)
  end

  def test_install_ignore_dependencies
    Dir.mkdir util_inst_bindir
    @spec.add_dependency 'b', '> 5'
    util_setup_gem
    @installer.ignore_dependencies = true

    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    gemdir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist?(gemdir)

    exe = File.join(gemdir, 'bin', 'executable')
    assert File.exist?(exe)
    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?
    assert File.exist?(File.join(gemdir, 'lib', 'code.rb'))

    assert File.exist?(File.join(@gemhome, 'specifications', @spec.spec_name))
  end

  def test_install_missing_dirs
    FileUtils.rm_f File.join(Gem.dir, 'cache')
    FileUtils.rm_f File.join(Gem.dir, 'docs')
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    use_ui @ui do
      @installer.install
    end

    File.directory? File.join(Gem.dir, 'cache')
    File.directory? File.join(Gem.dir, 'docs')
    File.directory? File.join(Gem.dir, 'specifications')

    assert File.exist?(File.join(@gemhome, 'cache', @spec.file_name))
    assert File.exist?(File.join(@gemhome, 'specifications', @spec.spec_name))
  end

  def test_install_post_build_false
    util_clear_gems

    Gem.post_build do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "post-build hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute File.exist? spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    refute File.exist? gem_dir
  end

  def test_install_post_build_nil
    util_clear_gems

    Gem.post_build do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert File.exist? spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    assert File.exist? gem_dir
  end

  def test_install_pre_install_false
    util_clear_gems

    Gem.pre_install do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "pre-install hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute File.exist? spec_file
  end

  def test_install_pre_install_nil
    util_clear_gems

    Gem.pre_install do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert File.exist? spec_file
  end

  def test_install_with_message
    @spec.post_install_message = 'I am a shiny gem!'

    use_ui @ui do
      path = Gem::Package.build @spec

      @installer = Gem::Installer.new path
      @installer.install
    end

    assert_match %r|I am a shiny gem!|, @ui.output
  end

  def test_install_wrong_ruby_version
    use_ui @ui do
      installer = Gem::Installer.new old_ruby_required
      e = assert_raises Gem::InstallError do
        installer.install
      end
      assert_equal 'old_ruby_required requires Ruby version = 1.4.6.',
                   e.message
    end
  end

  def test_install_wrong_rubygems_version
    spec = quick_spec 'old_rubygems_required', '1' do |s|
      s.required_rubygems_version = '< 0'
    end

    util_build_gem spec

    gem = File.join(@gemhome, 'cache', spec.file_name)

    use_ui @ui do
      @installer = Gem::Installer.new gem
      e = assert_raises Gem::InstallError do
        @installer.install
      end
      assert_equal 'old_rubygems_required requires RubyGems version < 0. ' +
        "Try 'gem update --system' to update RubyGems itself.", e.message
    end
  end

  def test_installation_satisfies_dependency_eh
    quick_spec 'a'

    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.installation_satisfies_dependency?(dep)

    dep = Gem::Dependency.new 'a', '> 2'
    refute @installer.installation_satisfies_dependency?(dep)
  end

  def test_shebang
    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_arguments
    util_make_exec @spec, "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_empty
    util_make_exec @spec, ''

    shebang = @installer.shebang 'executable'
    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env
    util_make_exec @spec, "#!/usr/bin/env ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_env_shebang
    util_make_exec @spec, ''
    @installer.env_shebang = true

    shebang = @installer.shebang 'executable'

    env_shebang = "/usr/bin/env" unless Gem.win_platform?

    assert_equal("#!#{env_shebang} #{Gem::ConfigMap[:ruby_install_name]}",
                 shebang)
  end

  def test_shebang_nested
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_nested_arguments
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version
    util_make_exec @spec, "#!/usr/bin/ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_arguments
    util_make_exec @spec, "#!/usr/bin/ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version_env
    util_make_exec @spec, "#!/usr/bin/env ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_custom
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = 'test'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!test", shebang
  end

  def test_shebang_custom_with_expands
    bin_env = win_platform? ? '' : '/usr/bin/env'
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = '1 $env 2 $ruby 3 $exec 4 $name'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!1 #{bin_env} 2 #{Gem.ruby} 3 executable 4 a", shebang
  end

  def test_shebang_custom_with_expands_and_arguments
    bin_env = win_platform? ? '' : '/usr/bin/env'
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = '1 $env 2 $ruby 3 $exec'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!1 #{bin_env} 2 #{Gem.ruby} -ws 3 executable", shebang
  end

  def test_unpack
    util_setup_gem

    dest = File.join @gemhome, 'gems', @spec.full_name

    @installer.unpack dest

    assert File.exist?(File.join(dest, 'lib', 'code.rb'))
    assert File.exist?(File.join(dest, 'bin', 'executable'))
  end

  def test_write_spec
    FileUtils.rm @spec.spec_file
    refute File.exist?(@spec.spec_file)

    @installer.spec = @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    assert File.exist?(@spec.spec_file)
    assert_equal @spec, eval(File.read(@spec.spec_file))
  end

  def test_write_spec_writes_cached_spec
    FileUtils.rm @spec.spec_file
    refute File.exist?(@spec.spec_file)

    @spec.files = %w[a.rb b.rb c.rb]

    @installer.spec = @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    # cached specs have no file manifest:
    @spec.files = []

    assert_equal @spec, eval(File.read(@spec.spec_file))
  end

  def test_dir
    assert_match %r!/gemhome/gems/a-2$!, @installer.dir
  end

  def old_ruby_required
    spec = quick_spec 'old_ruby_required', '1' do |s|
      s.required_ruby_version = '= 1.4.6'
    end

    util_build_gem spec

    spec.cache_file
  end

  def util_execless
    @spec = quick_spec 'z'
    util_build_gem @spec

    @installer = util_installer @spec, @gemhome
  end

  def util_conflict_executable wrappers
    conflict = quick_gem 'conflict' do |spec|
      util_make_exec spec
    end

    util_build_gem conflict

    installer = util_installer conflict, @gemhome
    installer.wrappers = wrappers
    installer.generate_bin
  end

  def mask
    0100755 & (~File.umask)
  end
end
