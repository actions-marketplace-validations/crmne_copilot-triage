# frozen_string_literal: true

require 'socket'
require_relative '../lib/assessment'

RSpec.describe 'Issue assessment Copilot integration', type: :task do
  let(:requests) { [] }

  around do |example|
    skip 'Install Copilot CLI to run this offline integration check' unless copilot_installed?

    server = TCPServer.new('127.0.0.1', 0)
    worker = serve_model(server, requests)
    previous = ENV.to_h
    ENV.update('COPILOT_OFFLINE' => 'true', 'COPILOT_PROVIDER_TYPE' => 'openai',
               'COPILOT_PROVIDER_BASE_URL' => "http://127.0.0.1:#{server.addr[1]}/v1",
               'COPILOT_PROVIDER_WIRE_API' => 'completions', 'COPILOT_PROVIDER_WIRE_MODEL' => 'gpt-5.6-luna')
    example.run
  ensure
    ENV.replace(previous) if previous
    worker&.kill&.join
    server&.close
  end

  it 'makes one request with no tools through the installed CLI, using an offline fake provider' do
    assessment = IssueAssessment.new('GITHUB_REPOSITORY' => 'crmne/ruby_llm', 'TRIAGE_NUMBER' => '123',
                                     'COPILOT_GITHUB_TOKEN' => 'offline-test', 'TRIAGE_CONFIG' => 'triage.yml')
    allow(assessment).to receive(:puts)

    response = assessment.send(:ask_copilot, 'Return JSON only: {"labels":[],"reply":null,"files":[]}')

    expect(JSON.parse(response)).to eq('labels' => [], 'reply' => nil, 'files' => [])
    expect(requests.size).to eq(1)
    expect(requests.first.fetch('tools', [])).to be_empty
  end

  it 'runs from another checkout, rereads GitHub, and reuses the cached response on a second preview' do
    Dir.mkdir('bin')
    File.write('bin/gh', <<~RUBY)
      #!/usr/bin/env ruby
      require 'json'
      payload = JSON.parse(STDIN.read)
      abort 'Unexpected mutation' if payload.fetch('query').include?('mutation')
      File.open('github-reads.txt', 'a') { |file| file.puts('read') }
      item = { id: 'item', title: 'Bug', body: 'A reproduction', closed: false,
               author: { login: 'reporter' }, comments: { nodes: [] } }
      puts JSON.generate(data: { repository: { issue: item, labels: { nodes: [] } } })
    RUBY
    File.chmod(0o755, 'bin/gh')
    environment = {
      'PATH' => "#{Dir.pwd}/bin:#{ENV.fetch('PATH')}", 'GITHUB_REPOSITORY' => 'crmne/ruby_llm',
      'COPILOT_GITHUB_TOKEN' => 'offline-test', 'TRIAGE_CONFIG' => 'triage.yml',
      'TRIAGE_NUMBER' => '123', 'TRIAGE_DRY_RUN' => 'true', 'TRIAGE_CACHE_DIR' => 'cache'
    }
    script = File.expand_path('../lib/assessment.rb', __dir__)

    first, errors, status = Open3.capture3(environment, RbConfig.ruby, script)
    expect(status.success?).to be(true), errors
    expect(first).to include('"labels":[]')
    second, errors, status = Open3.capture3(environment, RbConfig.ruby, script)
    expect(status.success?).to be(true), errors
    expect(second).to include('Reused a cached model response.')
    expect(File.readlines('github-reads.txt').size).to eq(4)
    expect(requests.size).to eq(1)
    expect(requests.first.fetch('tools', [])).to be_empty
  end

  def copilot_installed?
    ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, 'copilot')) }
  end

  def serve_model(server, requests)
    Thread.new do
      loop do
        socket = server.accept
        socket.gets
        headers = {}
        while (line = socket.gets) != "\r\n"
          name, value = line.split(':', 2)
          headers[name.downcase] = value.strip
        end
        requests << JSON.parse(socket.read(Integer(headers.fetch('content-length'))))
        body = completion
        socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n")
        socket.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
        socket.close
      end
    end
  end

  def completion
    chunk = {
      id: 'offline-completion', object: 'chat.completion.chunk', created: 1, model: 'gpt-5.6-luna',
      choices: [{ index: 0, finish_reason: 'stop',
                  delta: { role: 'assistant', content: '{"labels":[],"reply":null,"files":[]}' } }]
    }
    "data: #{JSON.generate(chunk)}\n\ndata: [DONE]\n\n"
  end
end
