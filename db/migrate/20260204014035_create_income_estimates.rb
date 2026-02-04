class CreateIncomeEstimates < ActiveRecord::Migration[8.0]
  def change
    create_table :income_estimates do |t|
      t.references :income_source, null: false, foreign_key: true
      t.string :cadence
      t.integer :interval
      t.integer :weekday
      t.integer :day_of_month
      t.integer :estimated_amount_cents
      t.date :start_on
      t.date :end_on
      t.boolean :active

      t.timestamps
    end
  end
end
