require "json"

namespace :budget do
  desc "Import a historical CSV into the ledger without duplicating transactions"
  task import_transactions: :environment do
    abort "FILE is required" if ENV["FILE"].blank?
    abort "ACCOUNT is required (the source CSV has no account column)" if ENV["ACCOUNT"].blank?
    abort "AFTER is required and must use YYYY-MM-DD" if ENV["AFTER"].blank?

    after = Date.iso8601(ENV.fetch("AFTER"))
    account = Account.find_by(import_key: ENV.fetch("ACCOUNT"))
    abort "Account not found for import key: #{ENV.fetch('ACCOUNT')}" unless account

    result = Transactions::HistoricalImport.call(
      file_path: ENV.fetch("FILE"),
      account: account,
      after: after,
      dry_run: ENV["DRY_RUN"] == "1"
    )

    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(result)
    else
      puts "Historical transaction import"
      puts "File: #{result.fetch(:file)}"
      puts "Account: #{result.fetch(:account_import_key)}"
      puts "After (exclusive): #{result.fetch(:after)}"
      puts "Dry run: #{result.fetch(:dry_run)}"
      puts "Total source rows: #{result.fetch(:total_source_rows)}"
      puts "Rows at/before cutoff: #{result.fetch(:rows_at_or_before_cutoff)}"
      puts "Eligible rows: #{result.fetch(:eligible_rows)}"
      puts "Already present by provenance: #{result.fetch(:already_present_count)}"
      puts "Definite existing matches: #{result.fetch(:definite_match_count)}"
      puts "Ambiguous possible duplicates: #{result.fetch(:ambiguous_count)}"
      puts "Clear new transactions: #{result.fetch(:clear_new_count)}"
      puts "Created transactions: #{result.fetch(:created_count)}"
      puts "Malformed rows: #{result.fetch(:malformed_count)}"
      puts ""
      puts "Apply result"
      puts "Eligible: #{result.fetch(:eligible)}"
      puts "Created: #{result.fetch(:created)}"
      puts "Matched existing: #{result.fetch(:matched_existing)}"
      puts "Ambiguous skipped: #{result.fetch(:ambiguous_skipped)}"
      puts "Failed: #{result.fetch(:failed)}"
      if result.fetch(:manual_review_required)
        puts "Completed successfully; manual review remains for skipped or malformed rows."
      else
        puts "Completed successfully; no manual review remains."
      end

      result.fetch(:ambiguous_rows).each do |row|
        puts "Ambiguous row #{row.fetch(:source_row_number)}: #{row.fetch(:date)} #{row.fetch(:description)} #{row.fetch(:signed_amount_cents)} cents"
        row.fetch(:candidate_transactions).each do |candidate|
          puts "  Candidate #{candidate.fetch(:id)}: #{candidate.fetch(:date)} #{candidate.fetch(:description)} #{candidate.fetch(:signed_amount_cents)} cents"
          puts "    Evidence: #{candidate.fetch(:evidence).to_json}"
        end
      end
    end
  rescue ArgumentError => e
    abort "Invalid AFTER date: #{e.message}"
  rescue MonthlyProcessing::PathSafety::UnsafePath,
         Transactions::HistoricalImport::InvalidSource,
         ActiveRecord::RecordInvalid => e
    abort e.message
  end

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
