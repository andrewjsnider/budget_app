require "json"

namespace :budget do
  desc "Process one private finance month and write a deterministic review bundle"
  task process_month: :environment do
    abort "MONTH is required and must use YYYY-MM" if ENV["MONTH"].blank?

    result = MonthlyProcessing::ProcessMonth.call(
      month: ENV.fetch("MONTH"),
      source_dir: ENV["SOURCE_DIR"],
      output_dir: ENV["OUTPUT_DIR"],
      dry_run: ENV["DRY_RUN"] == "1"
    )
    process_run = result.fetch(:process_run).merge(output_path: result.fetch(:output_path))

    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(process_run)
    else
      puts "Monthly processing: #{process_run.fetch(:status)}"
      puts "Month: #{process_run.fetch(:month)}"
      puts "Dry run: #{process_run.fetch(:dry_run)}"
      puts "Statements: #{process_run.fetch(:statement_count)}"
      puts "Newly staged or previewed: #{process_run.fetch(:staged_count)}"
      puts "Existing imports: #{process_run.fetch(:existing_count)}"
      puts "Blocked statements: #{process_run.fetch(:blocked_count)}"
      puts "Output: #{process_run.fetch(:output_path)}"
    end
  rescue MonthlyProcessing::Manifest::InvalidManifest,
         MonthlyProcessing::PathSafety::UnsafePath,
         MonthlyProcessing::OutputWriter::WriteError,
         MonthlyProcessing::ProcessMonth::ExistingImportMismatch,
         Statements::Parsers::GenericSignedCsv::FatalError,
         ActiveRecord::RecordInvalid => e
    abort e.message
  end

  desc "Report legacy ledger signs and blockers without changing data"
  task sign_preflight: :environment do
    report = Ledger::SignPreflight.call
    puts Ledger::SignPreflight.format(report)
    abort "Preflight found records requiring manual review." unless report[:safe_to_normalize]
  end

  desc "Normalize legacy ledger signs after an explicit reviewed preflight"
  task normalize: :environment do
    result = Ledger::SignNormalizer.call(confirm: ENV["CONFIRM"])

    if result[:status] == :already_completed
      puts "Signed ledger normalization was already completed; no changes made."
      next
    end

    puts "Signed ledger normalization completed."
    result[:changes].each do |change|
      puts "#{change[:type]} #{change[:id]}: #{change[:from_cents]} -> #{change[:to_cents]} cents"
    end
    puts "Changed #{result[:changes].size} records."
  rescue Ledger::SignNormalizer::ConfirmationRequired,
         Ledger::SignNormalizer::AmbiguousData,
         Ledger::SignNormalizer::MigrationRequired => e
    abort e.message
  end

  desc "Alias for budget:normalize"
  task normalize_signs: :normalize
end
