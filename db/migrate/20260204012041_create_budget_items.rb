class CreateBudgetItems < ActiveRecord::Migration[8.0]
  def change
    create_table :budget_items do |t|
      t.references :budget_month, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.integer :assigned_cents

      t.timestamps
    end
  end
end
