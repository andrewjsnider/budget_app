require "digest"

module FinancialActions
  class ClassifyTransactions
    MAX_TRANSFER_DATE_GAP = 3

    def self.call(input:, dry_run:)
      new(input:, dry_run:).call
    end

    def initialize(input:, dry_run:)
      @input = input
      @dry_run = dry_run
    end

    def call
      rows = Array(@input["classifications"])
      raise InputFile::InvalidInput, "classifications must contain at least one action" if rows.empty?

      results = rows.map { |row| process(row) }
      counts = results.group_by { |row| row.fetch(:status) }.transform_values(&:count)
      {
        policy_version: "transaction-classification-v1",
        dry_run: @dry_run,
        classified: counts.fetch("classified", 0),
        skipped: counts.fetch("skipped", 0),
        ambiguous: counts.fetch("ambiguous", 0),
        failed: counts.fetch("failed", 0),
        results: results
      }
    end

    private

    def process(row)
      kind = row.fetch("kind").to_s
      raise InputFile::InvalidInput, "Unsupported classification: #{kind}" unless TransactionClassification::KINDS.include?(kind)

      ids = Array(row["transaction_ids"] || row["transaction_id"]).map(&:to_i).uniq
      transactions = Transaction.includes(:account, :transaction_classification).where(id: ids).order(:id).to_a
      raise InputFile::InvalidInput, "Every transaction ID must exist" unless transactions.length == ids.length
      if TransactionClassification::TRANSFER_KINDS.include?(kind)
        classify_transfer(kind, transactions, row)
      else
        classify_single(kind, transactions, row)
      end
    rescue KeyError, InputFile::InvalidInput, ActiveRecord::RecordInvalid => e
      { status: "failed", reason: e.message, kind: row["kind"], transaction_ids: Array(row["transaction_ids"] || row["transaction_id"]) }
    end

    def classify_transfer(kind, transactions, row)
      raise InputFile::InvalidInput, "Transfer classifications require exactly two transactions" unless transactions.length == 2
      first, second = transactions
      raise InputFile::InvalidInput, "Transfer accounts must differ" if first.account_id == second.account_id
      raise InputFile::InvalidInput, "Transfer amounts must be exact opposites" unless first.amount_cents + second.amount_cents == 0
      if (first.occurred_on - second.occurred_on).to_i.abs > MAX_TRANSFER_DATE_GAP
        raise InputFile::InvalidInput, "Transfer dates must be within #{MAX_TRANSFER_DATE_GAP} days"
      end
      validate_transfer_accounts!(kind, transactions)
      existing = transactions.map(&:transaction_classification).compact
      if existing.any?
        expected_pairs = transactions.index_by(&:id)
        same = existing.length == 2 && existing.all? do |classification|
          classification.kind == kind && expected_pairs.key?(classification.paired_transaction_id)
        end
        return result(same ? "skipped" : "ambiguous", kind, transactions, same ? "already_classified" : "conflicting_classification")
      end

      group_key = Digest::SHA256.hexdigest([ "transaction-classification-v1", kind, *transactions.map(&:id).sort ].join("|"))
      unless @dry_run
        TransactionClassification.transaction do
          TransactionClassification.create!(ledger_transaction: first, paired_transaction: second, kind:, group_key:, source: source(row), evidence: evidence(row))
          TransactionClassification.create!(ledger_transaction: second, paired_transaction: first, kind:, group_key:, source: source(row), evidence: evidence(row))
        end
      end
      result("classified", kind, transactions, @dry_run ? "would_classify" : "classified", group_key: group_key)
    end

    def classify_single(kind, transactions, row)
      raise InputFile::InvalidInput, "#{kind} classifications require exactly one transaction" unless transactions.length == 1
      transaction = transactions.sole
      raise InputFile::InvalidInput, "#{kind} must be a positive inflow" unless transaction.amount_cents.positive?
      existing = transaction.transaction_classification
      return result(existing.kind == kind ? "skipped" : "ambiguous", kind, transactions,
        existing.kind == kind ? "already_classified" : "conflicting_classification") if existing

      unless @dry_run
        TransactionClassification.create!(ledger_transaction: transaction, kind:, source: source(row), evidence: evidence(row))
      end
      result("classified", kind, transactions, @dry_run ? "would_classify" : "classified")
    end

    def validate_transfer_accounts!(kind, transactions)
      kinds = transactions.map { |transaction| transaction.account.kind }
      if kind == "savings_transfer" && !kinds.include?("savings")
        raise InputFile::InvalidInput, "A savings transfer must include a savings account"
      end
      if kind == "credit_card_payment" && !kinds.include?("credit")
        raise InputFile::InvalidInput, "A credit-card payment must include a credit account"
      end
    end

    def source(row)
      row.fetch("source", "paperclip").to_s
    end

    def evidence(row)
      row.fetch("evidence", {}).merge("policy_version" => "transaction-classification-v1")
    end

    def result(status, kind, transactions, reason, **extra)
      { status:, kind:, transaction_ids: transactions.map(&:id), reason: }.merge(extra)
    end
  end
end
