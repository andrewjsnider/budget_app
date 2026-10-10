class AddStatementImportSourcePathConstraint < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :statement_imports,
                         "source_path !~ '(^|/)\\.\\.(/|$)' AND left(source_path, 1) <> '/'",
                         name: "statement_imports_relative_source_path"
  end
end
