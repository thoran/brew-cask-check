# test/brew-cask-check_test.rb

# 20261102
# 0.0.0

# Each test runs brew-cask-check as a subprocess with a fake brew first on the
# path, and asserts upon the calls made of it and the state it is left in. The
# fake brew keeps its taps under taps/, its trusted entries in trust.json, and
# takes a cask to be installed where installed exists. A subcommand named in
# failing, one a line, fails. style fails too where the cask wasn't copied into
# the tap, and untap where a cask from it is installed. Each call is written to
# calls, a call a line.

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

BIN = File.expand_path('../bin/brew-cask-check', __dir__)
TAP = 'someone/cask-check'
TAPPED_CASK = "#{TAP}/example"

FAKE_BREW = <<~'RUBY'
  #!/usr/bin/env ruby
  require 'fileutils'
  require 'json'
  directory = File.dirname(__FILE__)
  File.write(File.join(directory, 'calls'), "#{ARGV.join(' ')}\n", mode: 'a')
  trust_filepath = File.join(directory, 'trust.json')
  trust = File.exist?(trust_filepath) ? JSON.parse(File.read(trust_filepath)) : {}
  tap_directory = ->(tap){File.join(directory, 'taps', tap)}
  failing = File.exist?(File.join(directory, 'failing')) ? File.readlines(File.join(directory, 'failing'), chomp: true) : []
  exit 1 if failing.include?(ARGV[0])
  case ARGV[0]
  when '--repository'
    puts tap_directory.(ARGV[1])
  when 'tap-new'
    FileUtils.mkdir_p(tap_directory.(ARGV[1]))
  when 'untap'
    exit 1 if File.exist?(File.join(directory, 'installed_from_tap'))
    FileUtils.rm_rf(tap_directory.(ARGV[1]))
  when 'style'
    tap, token = ARGV.last.split('/').values_at(0..1).join('/'), ARGV.last.split('/').last
    exit 1 unless File.exist?(File.join(tap_directory.(tap), 'Casks', token[0], "#{token}.rb"))
  when 'trust', 'untrust'
    if ARGV[1] == '--json=v1'
      puts JSON.generate({'taps' => [], 'formulae' => [], 'casks' => [], 'commands' => []}.merge(trust))
    else
      type = {'--tap' => 'taps', '--formula' => 'formulae', '--cask' => 'casks', '--command' => 'commands'}[ARGV[1]]
      trust[type] = ARGV[0] == 'trust' ? (trust[type].to_a | [ARGV[2]]) : (trust[type].to_a - [ARGV[2]])
      File.write(trust_filepath, JSON.generate(trust))
    end
  when 'list'
    exit 1 unless File.exist?(File.join(directory, 'installed'))
  when 'install', 'reinstall'
    FileUtils.touch(File.join(directory, 'installed_from_tap')) unless ARGV.last.start_with?('homebrew/cask/')
  when 'uninstall'
    FileUtils.rm_f(File.join(directory, 'installed_from_tap'))
  end
RUBY

def fake_brew_directory
  @fake_brew_directory
end

def with_fake_brew
  Dir.mktmpdir do |directory|
    Dir.chdir(directory) do
      @fake_brew_directory = File.join(directory, 'bin')
      Dir.mkdir(fake_brew_directory)
      File.write(File.join(fake_brew_directory, 'brew'), FAKE_BREW)
      File.chmod(0755, File.join(fake_brew_directory, 'brew'))
      FileUtils.mkdir_p('Casks/e')
      File.write('Casks/e/example.rb', "cask 'example' do\nend\n")
      yield
    end
  end
end

def failing(*subcommands)
  File.write(File.join(fake_brew_directory, 'failing'), subcommands.join("\n"))
end

def installed
  FileUtils.touch(File.join(fake_brew_directory, 'installed'))
end

def trusted(entries)
  File.write(File.join(fake_brew_directory, 'trust.json'), JSON.generate(entries))
end

def trust
  filepath = File.join(fake_brew_directory, 'trust.json')
  File.exist?(filepath) ? JSON.parse(File.read(filepath)) : {}
end

def brew_calls
  File.readlines(File.join(fake_brew_directory, 'calls'), chomp: true)
end

def tap_exist?
  File.exist?(File.join(fake_brew_directory, 'taps', TAP))
end

def cask_check(*arguments)
  path = "#{fake_brew_directory}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
  stdout, stderr, status = Open3.capture3({'PATH' => path}, BIN, '-t', TAP, *arguments)
  [status.exitstatus, stdout + stderr]
end

describe 'brew-cask-check' do
  it 'styles and audits the cask in a tap of its own, and removes the tap' do
    with_fake_brew do
      status, output = cask_check('Casks/e/example.rb')
      _(status).must_equal 0
      _(output).must_include "style: passed\naudit: passed"
      _(brew_calls).must_include "style --cask #{TAPPED_CASK}"
      _(brew_calls).must_include "audit --cask --online #{TAPPED_CASK}"
      _(brew_calls.index("trust --cask #{TAPPED_CASK}")).must_be :<, brew_calls.index("audit --cask --online #{TAPPED_CASK}")
      _(brew_calls).wont_include "install --cask #{TAPPED_CASK}"
      _(tap_exist?).must_equal false
    end
  end

  it 'trusts the cask again before untapping, and ends with the trusted entries as they began' do
    with_fake_brew do
      trusted('taps' => ['someone/other'], 'casks' => ['someone/other/thing'])
      cask_check('Casks/e/example.rb')
      untap = brew_calls.index("untap #{TAP}")
      _(brew_calls[untap - 1]).must_equal "trust --cask #{TAPPED_CASK}"
      _(brew_calls[(untap + 1)..]).must_include "untrust --cask #{TAPPED_CASK}"
      _(trust.values_at('taps', 'casks')).must_equal [['someone/other'], ['someone/other/thing']]
    end
  end

  it 'leaves a cask trusted which was trusted beforehand' do
    with_fake_brew do
      trusted('casks' => [TAPPED_CASK])
      cask_check('Casks/e/example.rb')
      _(trust['casks']).must_equal [TAPPED_CASK]
    end
  end

  it 'audits as new with --new' do
    with_fake_brew do
      cask_check('-n', 'Casks/e/example.rb')
      _(brew_calls).must_include "audit --cask --online --new #{TAPPED_CASK}"
    end
  end

  it 'reports each check, runs the rest after one fails, still cleans up, and exits 1' do
    with_fake_brew do
      failing('style')
      status, output = cask_check('Casks/e/example.rb')
      _(status).must_equal 1
      _(output).must_include "style: failed\naudit: passed"
      _(tap_exist?).must_equal false
      _(trust['casks']).must_equal []
    end
  end

  it 'installs, uninstalls, and puts back the official cask where it was installed beforehand' do
    with_fake_brew do
      installed
      status, output = cask_check('-i', 'Casks/e/example.rb')
      _(status).must_equal 0
      _(output).must_include "install: passed\nuninstall: passed\nreinstall official: passed"
      calls = brew_calls
      _(calls.index("reinstall --cask #{TAPPED_CASK}")).must_be :<, calls.index("uninstall --cask #{TAPPED_CASK}")
      _(calls.index("uninstall --cask #{TAPPED_CASK}")).must_be :<, calls.index('install --cask homebrew/cask/example')
    end
  end

  it "installs and uninstalls, putting back nothing, where it wasn't installed beforehand" do
    with_fake_brew do
      cask_check('-i', 'Casks/e/example.rb')
      _(brew_calls).must_include "install --cask #{TAPPED_CASK}"
      _(brew_calls).must_include "uninstall --cask #{TAPPED_CASK}"
      _(brew_calls).wont_include 'install --cask homebrew/cask/example'
    end
  end

  it "says so where the tap can't be removed" do
    with_fake_brew do
      failing('uninstall')
      status, output = cask_check('-i', 'Casks/e/example.rb')
      _(status).must_equal 1
      _(output).must_include "brew untap #{TAP} failed."
      _(tap_exist?).must_equal true
    end
  end

  it 'refuses a tap which exists already, and leaves it be' do
    with_fake_brew do
      FileUtils.mkdir_p(File.join(fake_brew_directory, 'taps', TAP))
      status, output = cask_check('Casks/e/example.rb')
      _(status).must_equal 1
      _(output).must_include "#{TAP} exists already."
      _(brew_calls.grep(/\A(tap-new|untap|trust --cask)/)).must_be_empty
      _(tap_exist?).must_equal true
    end
  end

  it 'refuses a path with no cask at it' do
    with_fake_brew do
      status, output = cask_check('Casks/n/nonesuch.rb')
      _(status).must_equal 1
      _(output).must_include 'There is no cask at Casks/n/nonesuch.rb.'
    end
  end

  it 'shows the usage without exactly one cask' do
    with_fake_brew do
      status, output = cask_check
      _(status).must_equal 1
      _(output).must_include 'Usage: brew cask-check'
    end
  end
end
