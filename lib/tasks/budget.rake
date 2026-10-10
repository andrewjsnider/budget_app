namespace :budget do
  desc "Report legacy ledger signs and blockers without changing data"
  task sign_preflight: :environment do
    report = Ledger::SignPreflight.call
    puts Ledger::SignPreflight.format(report)
    abort "Preflight found records requiring manual review." unless report[:safe_to_normalize]
  end

  desc "Normalize legacy ledger signs after an explicit reviewed preflight"
  task normalize_signs: :environment do
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
end
