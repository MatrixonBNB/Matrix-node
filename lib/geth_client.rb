class GethClient
  class ClientError < StandardError; end
  
  attr_reader :node_url, :jwt_secret, :http

  def initialize(node_url)
    @node_url = node_url
    @jwt_secret = ENV.fetch('JWT_SECRET')
    @http = Net::HTTP::Persistent.new(name: "geth_client_#{node_url}")
  end

  def call(command, args = [])
    payload = {
      jsonrpc: "2.0",
      method: command,
      params: args,
      id: 1
    }
    
    send_request(payload)
  end
  alias :send_command :call

  def send_request(payload)
    uri = URI(@node_url)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{jwt}"
    request.body = payload.to_json

    response = Benchmark.msr("Calling: #{payload[:method]}") { @http.request(uri, request) }

    unless response.code.to_i == 200
      raise ClientError, response
    end

    parsed_response = JSON.parse(response.body)
    
    if parsed_response['error']
      raise ClientError.new(parsed_response['error'])
    end

    parsed_response['result']
  end

  def jwt_payload
    {
      iat: current_time.to_i
    }
  end

  def current_time
    Time.zone.now
  end
  
  def jwt
    JWT.encode(jwt_payload, jwt_secret.hex_to_bytes, 'HS256')
  end

  def shutdown
    @http.shutdown
  end
end
