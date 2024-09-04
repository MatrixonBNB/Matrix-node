class SolidityCompiler
  def initialize(filename_or_solidity_code)
    @solidity_file = filename_or_solidity_code
  end

  def self.reset_checksum
    @checksum = nil
  end
  
  class << self
    include Memery

    def compile(filename_or_solidity_code)
      checksum = directory_checksum

      memoized_compile(filename_or_solidity_code, checksum)
    end
    
    def directory_checksum
      directories = [
        Rails.root.join('lib', 'solidity'),
        Rails.root.join('node_modules')
      ]
      
      if ENV['LISTEN_FOR_SOLIDITY_CHANGES']
        calculate_checksum(directories)
      else
        @checksum ||= calculate_checksum(directories)
      end
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
      directory = Rails.root.join('lib', 'solidity', 'legacy')
      files = Dir.glob("#{directory}/**/*.sol").select { |f| File.file?(f) }
  
      results = Parallel.map(files, in_processes: Parallel.processor_count) do |file|
        checksum = directory_checksum
        memoized_compile(file, checksum)
      end
  
      # Combine results into a single hash
      combined_results = results.reduce({}) do |acc, result|
        acc.merge(result)
      end
  
      combined_results
    end
    
    def memoized_compile(filename, checksum)
      Rails.cache.fetch(['compile', checksum, filename.to_s]) do
        compile_solidity(filename)
      end
    end
    memoize :memoized_compile
  end
  
  def self.compile_solidity(file_path)
    if Rails.env.production?
      raise "Solidity compilation is disabled in production"
    end
    
    pragma_version = nil
    File.foreach(file_path) do |line|
      if line =~ /pragma solidity (.+);/
        pragma_version = $1.strip
        break
      end
    end

    raise "Pragma version not found in #{IO.read(file_path)}" unless pragma_version

    # Extract the version number (e.g., from "^0.8.0" to "0.8.0")
    version_match = pragma_version.match(/(\d+\.\d+\.\d+)/)
    raise "Invalid pragma version format in #{file_path}" unless version_match

    version = version_match[1]

    # Set the Solidity version using solc-select
    system("solc-select use #{version} --always-install")
    
    legacy_solidity = version.split('.').last(2).join('.').to_f < 8.17
    
    solc_args = [
      "solc",
      "--combined-json", "abi,bin,bin-runtime",
      "--optimize",
      "--optimize-runs", "200",
    ]

    # Append additional arguments if not legacy
    unless legacy_solidity
      solc_args += [
        "--via-ir",
        "--include-path", "node_modules/",
        "--base-path", Rails.root.join("lib", "solidity").to_s
      ]
    end
    
    solc_args += [file_path.to_s]
    
    Rails.logger.info("Running solc with arguments: #{solc_args.join(' ')}")

    # Compile with optimizer settings
    stdout, stderr, status = Open3.capture3(*solc_args)
    raise "Error running solc: #{stderr}" unless status.success?
  
    # Parse the JSON output
    output = JSON.parse(stdout)
  
    # Extract the contract names, bytecode, and ABI
    contract_data = {}
    output['contracts'].each do |contract_name, contract_info|
      name = contract_name.split(':').last
      contract_data[name] = {
        'bytecode' => contract_info['bin'],
        'abi' => contract_info['abi'],
        'bin_runtime' => contract_info['bin-runtime']
      }
    end
  
    # Return the hash mapping contract names to their bytecode and ABI
    contract_data
  end
end
