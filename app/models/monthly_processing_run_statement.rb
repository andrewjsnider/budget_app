class MonthlyProcessingRunStatement < ApplicationRecord
  STATUSES = %w[staged existing].freeze

  belongs_to :monthly_processing_run
  belongs_to :statement_import

  validates :statement_import_id, uniqueness: { scope: :monthly_processing_run_id }
  validates :position,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            uniqueness: { scope: :monthly_processing_run_id }
  validates :staging_status, inclusion: { in: STATUSES }
end
