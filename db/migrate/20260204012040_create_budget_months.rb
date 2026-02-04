class CreateBudgetMonths < ActiveRecord::Migration[8.0]
  def change
    create_table :budget_months do |t|
      t.date :month

      t.timestamps
    end
  end
end
