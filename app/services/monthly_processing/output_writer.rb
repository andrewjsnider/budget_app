require "fileutils"
require "tmpdir"

module MonthlyProcessing
  class OutputWriter
    FILE_MODE = 0o600
    DIRECTORY_MODE = 0o700
    FILENAMES = %w[
      process_run.json
      statements.json
      unresolved_items.json
      reconciliation_summary.json
      reconciliation_summary.md
    ].freeze

    class WriteError < StandardError; end

    def self.call(output_root:, run_name:, files:)
      new(output_root: output_root, run_name: run_name, files: files).call
    end

    def initialize(output_root:, run_name:, files:)
      @output_root = PathSafety.output_root(output_root)
      @run_name = run_name.to_s
      @files = files
    end

    def call
      validate!
      create_private_directory(@output_root)
      runs_root = @output_root.join("runs")
      create_private_directory(runs_root)
      target = runs_root.join(@run_name)
      raise WriteError, "Output run directory already exists: #{target}" if target.exist? || target.symlink?

      temporary = Pathname.new(Dir.mktmpdir(".#{@run_name}-", runs_root.to_s))
      File.chmod(DIRECTORY_MODE, temporary)
      begin
        FILENAMES.each { |filename| write_private_file(temporary.join(filename), @files.fetch(filename)) }
        File.rename(temporary, target)
        File.chmod(DIRECTORY_MODE, target)
      ensure
        FileUtils.remove_entry(temporary) if temporary.exist?
      end
      target
    rescue SystemCallError, KeyError => e
      raise WriteError, "Cannot write monthly output bundle: #{e.message}"
    end

    private

    def validate!
      unless @run_name.match?(/\A[a-z0-9][a-z0-9-]*\z/)
        raise WriteError, "Output run name is invalid"
      end
      missing = FILENAMES - @files.keys
      extra = @files.keys - FILENAMES
      raise WriteError, "Output bundle is missing files: #{missing.join(', ')}" if missing.any?
      raise WriteError, "Output bundle contains unknown files: #{extra.join(', ')}" if extra.any?
    end

    def create_private_directory(path)
      if path.exist?
        raise WriteError, "Output path is not a directory: #{path}" unless path.directory?
        raise WriteError, "Output directory cannot be a symbolic link: #{path}" if path.symlink?
      else
        FileUtils.mkdir_p(path, mode: DIRECTORY_MODE)
      end
      File.chmod(DIRECTORY_MODE, path)
    end

    def write_private_file(path, content)
      flags = File::WRONLY | File::CREAT | File::EXCL
      File.open(path, flags, FILE_MODE) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      File.chmod(FILE_MODE, path)
    end
  end
end
