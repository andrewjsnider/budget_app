class NormalizeUtilityCategoryGroup < ActiveRecord::Migration[8.0]
  class MigrationCategory < ActiveRecord::Base
    self.table_name = "categories"
  end

  def up
    MigrationCategory
      .where(kind: "expense", group: "Utilities")
      .update_all(group: "utilities", updated_at: Time.current)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "utility group normalization cannot distinguish migrated categories from later utility categories"
  end
end
