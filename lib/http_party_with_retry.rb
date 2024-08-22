module HttpPartyWithRetry
  extend self
  
  def get_with_retry(url, options = {}, retries = 5)
    request_with_retry(:get, url, options, retries)
  end

  def post_with_retry(url, options = {}, retries = 5)
    request_with_retry(:post, url, options, retries)
  end

  def put_with_retry(url, options = {}, retries = 5)
    request_with_retry(:put, url, options, retries)
  end

  def delete_with_retry(url, options = {}, retries = 5)
    request_with_retry(:delete, url, options, retries)
  end

  private

  def request_with_retry(method, url, options, retries)
    begin
      response = HTTParty.send(method, url, options)
      
      if response.code != 200
        raise "HTTP error: #{response.code} #{response.message}. Full URL: #{response.request.last_uri}"
      end

      response
    rescue StandardError => e
      full_url = e.respond_to?(:response) ? e.response&.request&.last_uri : url
      
      puts "Retrying #{retries} more times (last error: #{e.message.inspect})"
      
      retries -= 1
      if retries > 0
        sleep 1
        retry
      else
        raise "Failed after #{retries} retries: #{e.message.inspect}. Full URL: #{full_url}"
      end
    end
  end
end
