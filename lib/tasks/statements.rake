require "json"

namespace :statements do
  desc "Stage a private statement CSV without creating ledger transactions"
  task stage: :environment do
    required = %w[ACCOUNT FILE PARSER]
    missing = required.select { |name| ENV[name].blank? }
    abort "Missing required environment variables: #{missing.join(', ')}" if missing.any?

    parse_date = lambda do |name|
      value = ENV[name]
      next if value.blank?

      Date.iso8601(value)
    rescue Date::Error
      abort "#{name} must use YYYY-MM-DD"
    end

    ending_balance_cents = if ENV["ENDING_BALANCE"].present?
      Statements::DecimalCents.call(ENV["ENDING_BALANCE"])
    end

    result = Statements::StageImport.call(
      account: ENV.fetch("ACCOUNT"),
      file_path: ENV.fetch("FILE"),
      parser_key: ENV.fetch("PARSER"),
      started_on: parse_date.call("STARTS_ON"),
      ended_on: parse_date.call("ENDS_ON"),
      statement_ending_balance_cents: ending_balance_cents,
      dry_run: ENV["DRY_RUN"] == "1"
    )

    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(result)
    else
      puts "Statement staging result"
      result.each do |key, value|
        next if key == :errors

        puts "#{key}: #{value.nil? ? '-' : value}"
      end
      result.fetch(:errors).each do |error|
        puts "error row=#{error.fetch(:source_row_number)} code=#{error.fetch(:error_code)} message=#{error.fetch(:error_message)}"
      end
    end
  rescue Statements::DecimalCents::InvalidAmount,
         Statements::Parsers::UnknownParser,
         Statements::Parsers::GenericSignedCsv::FatalError,
         Statements::StageImport::Error,
         ActiveRecord::RecordInvalid => e
    abort e.message
  end
end
