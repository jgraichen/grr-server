# rubocop:disable all

module Grr
  # Grpc service implementation
  class GrpcServer < Grr::RestService::Service

    attr_reader :app, :logger

    def initialize(app, logger)
      @app = app
      @logger = logger
      @mutex = Mutex.new

      logf = File.open('trace.log', 'w')

      set_trace_func proc {|event, file, line, id, _binding, classname|
        logf << format("[#{Thread.current.object_id}] %8s %s:%-2d %10s %8s\n",
                       event, file, line, id, classname)
      }
    end

    # do_request implements the DoRequest rpc method.
    def do_request(rest_req, _call)
      @mutex.synchronize do
        logger.info("Grpc-Rest requested received. Location: #{rest_req.location};")

        # Duplicate is needed, because rest_req['body'] is frozen.
        bodyDup = rest_req['body'].dup
        bodyDup.force_encoding "ASCII-8BIT" # Rack rquires this encoding
        qsDup = rest_req['queryString'].dup
        qsDup.force_encoding "ASCII-8BIT"

        # Create rack env for the request
        env = new_env(rest_req['method'],rest_req['location'],qsDup,bodyDup)

        logger.info "[#{Thread.current.object_id}] ==> #{env['REQUEST_METHOD']} #{env['REQUEST_PATH']}"

        # Execute the app's .call() method (Rack standard)
        # blocks execution, sync call
        t1 = Time.now

        body = []
        status = nil
        headers = nil

        Thread.new do
          logger.debug "[#{Thread.current.object_id}] Call application"

          begin
            status, headers, out = app.call(env)

            logger.debug "[#{Thread.current.object_id}] Processing application response"

            out.each {|s| body << s.to_str }
          rescue Exception => err
            logger.debug "[#{Thread.current.object_id}] Application call errored: #{err}"
          ensure
            logger.debug "[#{Thread.current.object_id}] Application call finished"
          end
        end.join

        t2 = Time.now
        msecs = time_diff_milli t1, t2

        logger.info "[#{Thread.current.object_id}] <== #{status} (#{msecs.round(2)}ms)"

        # Parse the body (may be chunked)
        bodyString = reassemble_chunks(body)
        # File.write('./out.html',bodyString) # For debugging. Errors are returned in html sometimes, hard to read on the command line.

        # ActiveRecord::Base.clear_active_connections!

        # Create new Response Object
        Grr::RestResponse.new(headers: headers.to_s, status: status, body: bodyString)
      end
    rescue => err
      logger.error "[#{Thread.current.object_id}] === #{err}"
    ensure
      logger.info "[#{Thread.current.object_id}] === do_request returned"
    end

    # Rack needs ad ENV to process the request
    # see http://www.rubydoc.info/github/rack/rack/file/SPEC
    def new_env(method, location, queryString, body)
      {
        'REMOTE_ADDR'      => '::1',
        'REQUEST_METHOD'   => method,
        'HTTP_ACCEPT'      => 'application/json', # hardcoded TODO use request header
        'CONTENT_TYPE'     => 'application/json', # hardcoded TODO use request header
        'SCRIPT_NAME'      => '',
        'PATH_INFO'        => location,
        'REQUEST_PATH'     => location,
        'REQUEST_URI'      => location,
        'QUERY_STRING'     => queryString,
        'CONTENT_LENGTH'   => body.bytesize.to_s,
        'SERVER_NAME'      => 'localhost',
        'SERVER_PORT'      => '6575',
        'HTTP_HOST'        => 'localhost:6575',
        'HTTP_USER_AGENT'  => 'grr/0.1.0',
        'SERVER_PROTOCOL'  => 'HTTP/1.0',
        'HTTP_VERSION'     => 'HTTP/1.0',
        'rack.version'     => Rack.version.split('.'),
        'rack.url_scheme'  => 'http',
        'rack.input'       => StringIO.new(body),
        'rack.errors'      => StringIO.new(''),
        'rack.multithread' => true,
        'rack.run_once'    => true,
        'rack.multiprocess'=> false,
      }
    end

    private
    def time_diff_milli(start, finish)
      (finish - start) * 1000.0
    end

    def reassemble_chunks raw_data
      reassembled_data = ""
      position = 0
      raw_data.each do |chunk|
        end_of_chunk_size = chunk.index "\r\n"
        if end_of_chunk_size.nil?
          # logger.info("no chunk found")
          reassembled_data << chunk
          next
        end
        chunk_size = chunk[0..(end_of_chunk_size-1)].to_i 16 # chunk size represented in hex
        # TODO ensure next two characters are "\r\n"
        position = end_of_chunk_size + 2
        end_of_content = position + chunk_size
        str = chunk[position..end_of_content-1]
        reassembled_data << str
        # TODO ensure next two characters are "\r\n"
      end
      reassembled_data
    end

  end
end
