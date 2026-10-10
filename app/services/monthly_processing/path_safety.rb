require "pathname"

module MonthlyProcessing
  class PathSafety
    class UnsafePath < StandardError; end

    def self.source_root(path)
      root = Pathname.new(path.to_s).expand_path
      raise UnsafePath, "Source directory does not exist: #{root}" unless root.directory?
      raise UnsafePath, "Source directory cannot be a symbolic link" if root.symlink?

      root = root.realpath
      outside_repository!(root, label: "Source directory")
      root
    rescue SystemCallError => e
      raise UnsafePath, "Cannot inspect source directory: #{e.message}"
    end

    def self.contained_file(root:, relative_path:, label: "Statement file")
      relative = Pathname.new(relative_path.to_s)
      if relative.absolute? || relative.each_filename.include?("..") || relative.to_s.blank?
        raise UnsafePath, "#{label} must be a relative path without traversal"
      end

      candidate = root.join(relative).cleanpath
      raise UnsafePath, "#{label} does not exist: #{relative}" unless candidate.file?
      raise UnsafePath, "#{label} cannot be a symbolic link: #{relative}" if candidate.symlink?

      real_path = candidate.realpath
      root_prefix = "#{root.realpath}#{File::SEPARATOR}"
      unless real_path.to_s.start_with?(root_prefix)
        raise UnsafePath, "#{label} must remain inside the source directory"
      end

      real_path
    rescue SystemCallError => e
      raise UnsafePath, "Cannot inspect #{label.downcase}: #{e.message}"
    end

    def self.output_root(path)
      output = Pathname.new(path.to_s).expand_path
      outside_repository!(canonical_path(output), label: "Output directory")
      if output.exist?
        raise UnsafePath, "Output path must be a directory" unless output.directory?
        raise UnsafePath, "Output directory cannot be a symbolic link" if output.symlink?
      end
      output
    rescue SystemCallError => e
      raise UnsafePath, "Cannot inspect output directory: #{e.message}"
    end

    def self.outside_repository!(path, label:)
      repository = Rails.root.realpath
      expanded = Pathname.new(path.to_s).expand_path
      repository_prefix = "#{repository}#{File::SEPARATOR}"
      if expanded == repository || expanded.to_s.start_with?(repository_prefix)
        raise UnsafePath, "#{label} must be outside the application repository"
      end
    end

    def self.canonical_path(path)
      current = Pathname.new(path.to_s).expand_path
      missing = []
      until current.exist?
        missing.unshift(current.basename)
        parent = current.parent
        raise UnsafePath, "Cannot resolve output path" if parent == current

        current = parent
      end
      raise UnsafePath, "Output path cannot traverse a symbolic link" if current.symlink?

      missing.reduce(current.realpath) { |result, component| result.join(component) }
    end

    private_class_method :canonical_path
  end
end
