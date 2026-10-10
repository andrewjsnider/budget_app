class StatementImport < ApplicationRecord
  STATUSES = %w[staged failed reviewed superseded].freeze

  belongs_to :account
  has_many :statement_entries, dependent: :restrict_with_error
  has_one :reconciliation, dependent: :restrict_with_error

  validates :source_filename, :source_path, :file_sha256, :parser_key, :parser_version, presence: true
  validates :file_sha256,
            format: { with: /\A[0-9a-f]{64}\z/ },
            uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
  validates :row_count, :parsed_count, :failed_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :counts_are_consistent
  validate :source_path_is_relative_and_safe
  validate :source_identity_fields_are_immutable, on: :update
  validate :reviewed_statement_fields_are_immutable, on: :update

  private

  def counts_are_consistent
    return if row_count.to_i == parsed_count.to_i + failed_count.to_i

    errors.add(:row_count, "must equal parsed count plus failed count")
  end

  def source_path_is_relative_and_safe
    path = Pathname.new(source_path.to_s)
    return unless path.absolute? || path.each_filename.include?("..")

    errors.add(:source_path, "must be a private relative path without traversal")
  end

  def source_identity_fields_are_immutable
    immutable_fields = %w[account_id source_filename source_path file_sha256 parser_key parser_version]
    changed_fields = changes_to_save.keys & immutable_fields
    return if changed_fields.empty?

    errors.add(:base, "Statement source identity cannot change: #{changed_fields.join(', ')}")
  end

  def reviewed_statement_fields_are_immutable
    return unless attribute_in_database("status") == "reviewed"

    protected_fields = %w[
      account_id started_on ended_on statement_ending_balance_cents status
      row_count parsed_count failed_count
    ]
    changed_fields = changes_to_save.keys & protected_fields
    return if changed_fields.empty?

    errors.add(:base, "Reviewed statement fields cannot change: #{changed_fields.join(', ')}")
  end
end
