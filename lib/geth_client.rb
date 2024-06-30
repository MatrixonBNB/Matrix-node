class GethClient
  class ClientError < StandardError; end
  
  attr_reader :node_url, :jwt_secret

  def initialize(node_url)
    @node_url = node_url
    @jwt_secret = ENV.fetch('JWT_SECRET')
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
    options = {
      body: payload.to_json,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{jwt}"
      }
    }
    response = HTTParty.post(@node_url, options)
    
    unless response.code == 200
      raise ClientError, response
    end
    
    raise ClientError.new(response.parsed_response['error']) if response.parsed_response['error']
    
    response.parsed_response['result']
  end

  def jwt
    payload = {
      iat: Time.now.to_i
    }
    
    JWT.encode(payload, jwt_secret.hex_to_bytes, 'HS256')
  end
end
