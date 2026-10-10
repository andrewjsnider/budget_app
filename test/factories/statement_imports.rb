FactoryBot.define do
  factory :statement_import do
    association :account
    sequence(:source_filename) { |number| "statement-#{number}.csv" }
    sequence(:source_path) { |number| "2026-10/statement-#{number}.csv" }
    sequence(:file_sha256) { |number| format("%064x", number) }
    parser_key { "generic_signed_csv" }
    parser_version { "1" }
    started_on { Date.new(2026, 10, 1) }
    ended_on { Date.new(2026, 10, 31) }
    statement_ending_balance_cents { 0 }
    status { "staged" }
    row_count { 0 }
    parsed_count { 0 }
    failed_count { 0 }
  end
end
