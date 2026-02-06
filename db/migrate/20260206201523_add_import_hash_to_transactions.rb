class AddImportHashToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :import_hash, :string
    add_index :transactions, [:account_id, :import_hash], unique: true
  end
end
