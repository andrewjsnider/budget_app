class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name
      t.string :kind
      t.string :group
      t.boolean :archived

      t.timestamps
    end
  end
end
