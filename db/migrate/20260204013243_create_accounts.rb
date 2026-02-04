class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name
      t.string :kind
      t.boolean :archived

      t.timestamps
    end
  end
end
