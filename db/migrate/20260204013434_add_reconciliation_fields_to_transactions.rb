class AddReconciliationFieldsToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :cleared, :boolean, default: false, null: false
    add_column :transactions, :reconciled_at, :datetime
  end
end
