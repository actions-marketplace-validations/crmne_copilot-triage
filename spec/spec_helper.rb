# frozen_string_literal: true

require 'rspec'
require 'tmpdir'
require 'fileutils'

RSpec.configure do |config|
  config.around do |example|
    Dir.mktmpdir('triage-repository-') do |directory|
      FileUtils.cp_r(Dir.glob(File.join(__dir__, 'fixtures', '*')), directory)
      Dir.chdir(directory) { example.run }
    end
  end
end
