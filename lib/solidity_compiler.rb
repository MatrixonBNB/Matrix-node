class SolidityCompiler
  class << self
    include Memery

    def compile(filename_or_solidity_code)
      checksum = directory_checksum
      memoized_compile(filename_or_solidity_code, checksum)
    end
    
    def reset_checksum
      @checksum = nil
    end
    
    def directory_checksum
      directories = [
        Rails.root.join('contracts')
      ]
      
      @checksum ||= calculate_checksum(directories)
    end
  
    def calculate_checksum(directories)
      files = directories.flat_map { |directory| Dir.glob("#{directory}/**/*.sol").select { |f| File.file?(f) } }
      digest = Digest::SHA256.new
      files.each do |file|
        digest.update(File.read(file))
      end
      digest.hexdigest
    end

    def compile_all_legacy_files
      directory = Rails.root.join('contracts', 'src', 'predeploys')
      files = Dir.glob("#{directory}/**/*.sol").select do |f|
        File.file?(f) && f.split("/").last.match(/V[a-f0-9]{3}\.sol$/i)
      end
      
      foundry_root = Rails.root.join('contracts')
      build_command = "cd #{foundry_root} && forge build"
      puts "Running command: #{build_command}"
      
      success = system(build_command)
        
      unless success
        raise "Error running forge build. Exit status: #{$?.exitstatus}"
      end
      checksum = directory_checksum
      
      results = files.map do |file|
        memoized_compile(file, checksum)
      end

      results.reduce({}, :merge)
    end

    def memoized_compile(filename, checksum)
      Rails.cache.fetch(['compile', checksum, filename.to_s]) do
        compile_solidity(filename)
      end
    end
    memoize :memoized_compile

    def compile_solidity(file_path)
      raise "Solidity compilation is disabled in production" if Rails.env.production?

      # Ensure file_path is a string
      file_path = file_path.to_s

      foundry_root = Rails.root.join('contracts')
      file_path = foundry_root.join('src', file_path) unless file_path.start_with?(foundry_root.to_s)
      
      contract_name = File.basename(file_path, '.sol')
      
      json_file_path = foundry_root.join('forge-artifacts', "#{File.basename(file_path)}", "#{contract_name}.json")
      contract_data = JSON.parse(File.read(json_file_path))
        
      {
        contract_name => {
          'abi' => contract_data['abi'],
          'bytecode' => contract_data['bytecode']['object'].sub(/\A0x/, ''),
          'bin_runtime' => contract_data['deployedBytecode']['object'].sub(/\A0x/, '')
        }
      }
    end
  end

  def initialize(filename_or_solidity_code)
    @solidity_file = filename_or_solidity_code
  end
end
