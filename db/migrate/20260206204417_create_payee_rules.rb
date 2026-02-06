class CreatePayeeRules < ActiveRecord::Migration[8.0]
def change
    create_table :payee_rules do |t|
      t.string :pattern, null: false
      t.string :match_type, null: false, default: "contains"
      t.references :category, null: false, foreign_key: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :payee_rules, [:active, :match_type]
  end
end
