class CreateRecurringExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_expenses do |t|
      t.string :name
      t.boolean :active
      t.references :account, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :cadence
      t.integer :interval
      t.integer :weekday
      t.integer :day_of_month
      t.integer :estimated_amount_cents
      t.date :start_on
      t.date :end_on

      t.timestamps
    end
  end
end
