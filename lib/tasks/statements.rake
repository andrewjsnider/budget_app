require "json"

namespace :statements do
  parse_opening_balance = lambda do
    next if ENV["OPENING_BALANCE"].blank?

    Statements::DecimalCents.call(ENV["OPENING_BALANCE"])
  end

  find_import = lambda do
    abort "IMPORT_ID is required" if ENV["IMPORT_ID"].blank?

    StatementImport.find(ENV.fetch("IMPORT_ID"))
  end

  find_entry = lambda do
    abort "ENTRY_ID is required" if ENV["ENTRY_ID"].blank?

    StatementEntry.find(ENV.fetch("ENTRY_ID"))
  end

  find_transaction = lambda do
    abort "TRANSACTION_ID is required" if ENV["TRANSACTION_ID"].blank?

    Transaction.find(ENV.fetch("TRANSACTION_ID"))
  end

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


  desc "Review deterministic matches and reconciliation readiness without writing"
  task review: :environment do
    statement_import = find_import.call
    result = Statements::ReviewImport.call(
      statement_import: statement_import,
      opening_balance_cents: parse_opening_balance.call
    )

    if ENV["JSON"] == "1"
      puts JSON.pretty_generate(result)
    else
      puts "Statement import: #{result.fetch(:statement_import_id)}"
      puts "Account: #{result.fetch(:account)}"
      puts "Rows: #{result.fetch(:rows)}"
      puts "Failed: #{result.fetch(:failed)}"
      puts "Matched: #{result.fetch(:matched)}"
      puts "New transactions: #{result.fetch(:new_transactions)}"
      puts "Unmatched: #{result.fetch(:unmatched)}"
      puts "Ambiguous: #{result.fetch(:ambiguous)}"
      puts "Ignored: #{result.fetch(:ignored)}"
      puts "Opening balance cents: #{result.fetch(:opening_balance_cents) || '-'}"
      puts "Statement activity cents: #{result.fetch(:activity_cents)}"
      puts "Expected ending balance cents: #{result.fetch(:statement_ending_balance_cents) || '-'}"
      puts "Computed ending balance cents: #{result.fetch(:computed_ending_balance_cents) || '-'}"
      puts "Difference cents: #{result.fetch(:difference_cents) || '-'}"
      puts "Ready to finalize: #{result.fetch(:ready_to_finalize)}"
      puts "Blockers:"
      if result.fetch(:blockers).empty?
        puts "  none"
      else
        result.fetch(:blockers).each { |blocker| puts "  #{blocker.fetch(:code)}: #{blocker.fetch(:message)}" }
      end
      puts "Entries:"
      result.fetch(:entries).each do |entry|
        puts "  row=#{entry.fetch(:source_row_number)} entry=#{entry.fetch(:entry_id)} " \
          "state=#{entry.fetch(:resolution_status)} amount_cents=#{entry.fetch(:amount_cents)} " \
          "action=#{entry.fetch(:recommended_action)} candidates=#{entry.fetch(:candidate_transactions).size}"
      end
      result.fetch(:failed_entries).each do |entry|
        puts "  row=#{entry.fetch(:source_row_number)} entry=#{entry.fetch(:entry_id)} " \
          "parse_error=#{entry.fetch(:error_code)} message=#{entry.fetch(:error_message)}"
      end
    end
  rescue Statements::DecimalCents::InvalidAmount, ActiveRecord::RecordNotFound => e
    abort e.message
  end

  desc "Apply only narrow deterministic matches; never create ledger transactions"
  task apply_matches: :environment do
    result = Statements::ApplyMatches.call(statement_import: find_import.call)
    puts JSON.pretty_generate(result.merge(statement_import_id: ENV.fetch("IMPORT_ID")))
  rescue ActiveRecord::RecordNotFound, StatementEntries::MatchExisting::InvalidMatch => e
    abort e.message
  end

  desc "Explicitly match a statement entry to an existing transaction"
  task match: :environment do
    entry = StatementEntries::MatchExisting.call(
      entry: find_entry.call,
      transaction: find_transaction.call,
      reason: ENV["REASON"]
    )
    puts JSON.pretty_generate(
      status: entry.resolution_status,
      entry_id: entry.id,
      transaction_id: entry.transaction_id
    )
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         StatementEntries::MatchExisting::InvalidMatch => e
    abort e.message
  end

  desc "Explicitly create and link a ledger transaction from a statement entry"
  task create_transaction: :environment do
    transaction = StatementEntries::CreateTransaction.call(entry: find_entry.call)
    puts JSON.pretty_generate(
      status: "new_transaction",
      entry_id: ENV.fetch("ENTRY_ID"),
      transaction_id: transaction.id
    )
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         StatementEntries::CreateTransaction::InvalidCreation => e
    abort e.message
  end

  desc "Reject one candidate for an unresolved or ambiguous statement entry"
  task reject_candidate: :environment do
    abort "REASON is required" if ENV["REASON"].blank?

    resolution = StatementEntries::RejectCandidate.call(
      entry: find_entry.call,
      transaction: find_transaction.call,
      reason: ENV.fetch("REASON")
    )
    puts JSON.pretty_generate(
      status: "candidate_rejected",
      resolution_id: resolution.id,
      entry_id: resolution.statement_entry_id,
      transaction_id: resolution.transaction_id
    )
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         StatementEntries::RejectCandidate::InvalidRejection => e
    abort e.message
  end

  desc "Explicitly ignore one statement entry with an auditable reason"
  task ignore: :environment do
    abort "REASON is required" if ENV["REASON"].blank?

    entry = StatementEntries::Ignore.call(entry: find_entry.call, reason: ENV.fetch("REASON"))
    puts JSON.pretty_generate(
      status: entry.resolution_status,
      entry_id: entry.id,
      reason: entry.ignored_reason
    )
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         StatementEntries::Ignore::InvalidIgnore => e
    abort e.message
  end

  desc "Finalize an exact, fully resolved statement reconciliation"
  task finalize: :environment do
    result = Reconciliations::FinalizeStatement.call(
      statement_import: find_import.call,
      opening_balance_cents: parse_opening_balance.call
    )
    puts JSON.pretty_generate(result)
  rescue Statements::DecimalCents::InvalidAmount, ActiveRecord::RecordNotFound,
         ActiveRecord::RecordInvalid, Reconciliations::FinalizeStatement::CannotFinalize => e
    abort e.message
  end
end
