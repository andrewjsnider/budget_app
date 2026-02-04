class AddAccountToTransactions < ActiveRecord::Migration[8.0]
  def up
    add_reference :transactions, :account, foreign_key: true

    Transaction.reset_column_information

    Transaction.where(account_id: nil).where.not(account_name: [nil, ""]).find_each do |t|
      account = Account.find_or_create_by!(name: t.account_name) do |a|
        a.kind = "asset"
        a.archived = false
      end
      t.update_columns(account_id: account.id)
    end
  end

  def down
    remove_reference :transactions, :account, foreign_key: true
  end
end
