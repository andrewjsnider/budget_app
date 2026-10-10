module Statements
  module Parsers
    class Registry
      ADAPTERS = {
        "generic_signed_csv" => GenericSignedCsv
      }.freeze

      def self.fetch(key)
        ADAPTERS.fetch(key.to_s) do
          raise UnknownParser, "Unknown statement parser: #{key.inspect}"
        end
      end

      def self.keys
        ADAPTERS.keys.sort
      end
    end
  end
end
