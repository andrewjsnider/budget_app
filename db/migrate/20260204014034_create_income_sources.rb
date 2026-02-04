class CreateIncomeSources < ActiveRecord::Migration[8.0]
  def change
    create_table :income_sources do |t|
      t.string :name
      t.string :kind
      t.boolean :active
      t.references :account, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
  end
end
