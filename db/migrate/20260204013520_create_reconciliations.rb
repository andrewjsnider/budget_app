class CreateReconciliations < ActiveRecord::Migration[8.0]
  def change
    create_table :reconciliations do |t|
      t.references :account, null: false, foreign_key: true
      t.date :starts_on
      t.date :ends_on
      t.integer :statement_ending_balance_cents
      t.datetime :reconciled_at

      t.timestamps
    end
  end
end
