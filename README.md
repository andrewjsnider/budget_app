# Budget App

## Money conventions

Ledger transactions use signed integer cents. Inflows are positive, outflows are negative, and zero-value transactions are invalid. Account balances and reconciliation calculations sum those signed values directly.

Income estimates and recurring expenses are both entered and stored as positive magnitudes. Projection code adds income estimates and subtracts recurring expenses. This keeps the human-entered schedule forms consistent while preserving a single signed convention in the ledger.

Before converting a database created under the legacy unsigned-expense behavior, run `bin/rails budget:sign_preflight`. Review and resolve every blocker before running the separately confirmed normalization command documented by that task.

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
