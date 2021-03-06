#!/usr/bin/env ruby

this_dir = File.expand_path(File.dirname(__FILE__))
lib_dir = File.join(this_dir, '../lib')
$LOAD_PATH.unshift(lib_dir) unless $LOAD_PATH.include?(lib_dir)

require 'grr-client'
require 'json'
require 'dotenv/load'
require_relative '../test/requests/grpc'

def benchmark
  execution_times, threads, *rest = ARGV
  execution_times = execution_times.to_i
  threads = threads.to_i

  logger = Logger.new(STDOUT)

  host = ENV['GRR_HOST'] || 'localhost'
  port = ENV['GRR_PORT'] || '6575'

  client = Grr::Client.new(Host: host, Port: port)

  logger.info 'Requesting login'
  requestBuilder = RequestBuilder::Grpc.new client

  resp, msecs = requestBuilder.loginRequest
  json = JSON.parse(resp.body)
  sessionId = json['id']
  logger.info "Session id is #{sessionId}"

  requestBuilder.concurrentSessionRequests sessionId, execution_times, threads
end

benchmark
