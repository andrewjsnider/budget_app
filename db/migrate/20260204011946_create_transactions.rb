class CreateTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :transactions do |t|
      t.date :occurred_on
      t.string :description
      t.integer :amount_cents
      t.string :account_name
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
