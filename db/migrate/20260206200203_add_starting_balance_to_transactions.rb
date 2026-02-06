class AddStartingBalanceToTransactions < ActiveRecord::Migration[8.0]
  def change
      add_column :transactions, :starting_balance, :boolean, null: false, default: false

      add_index :transactions,
                :account_id,
                unique: true,
                where: "starting_balance = true",
                name: "index_transactions_one_starting_balance_per_account"
  end
end
