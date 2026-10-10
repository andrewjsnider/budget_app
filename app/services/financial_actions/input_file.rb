require "json"

module FinancialActions
  class InputFile
    class InvalidInput < StandardError; end

    def self.call(path)
      source = MonthlyProcessing::PathSafety.source_file(path, label: "Financial action input")
      parsed = JSON.parse(File.read(source))
      raise InvalidInput, "Financial action input must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise InvalidInput, "Invalid financial action JSON: #{e.message}"
    end
  end
end
