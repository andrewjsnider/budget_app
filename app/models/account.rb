class Account < ApplicationRecord
  has_many :transactions, dependent: :restrict_with_error
  has_many :reconciliations, dependent: :destroy
  has_many :statement_imports, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, inclusion: { in: %w[checking savings credit cash] }
  validates :import_key, presence: true, unless: :archived?
  validates :import_key,
            uniqueness: true,
            format: {
              with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
              message: "must use lowercase letters, numbers, and single hyphens"
            },
            allow_blank: true
  validate :import_key_is_immutable_after_statement_import

  def balance_cents(as_of: nil)
    scope = transactions
    scope = scope.where("occurred_on <= ?", as_of) if as_of.present?
    scope.sum(:amount_cents)
  end

  def has_starting_balance?
    transactions.where(starting_balance: true).exists?
  end

  private

  def import_key_is_immutable_after_statement_import
    return unless will_save_change_to_import_key?
    return unless statement_imports.exists?

    errors.add(:import_key, "cannot change after a statement has been staged")
  end
end
