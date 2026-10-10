require "test_helper"
require "rake"

class FinancialActionsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("budget:categorize")
    @input_path = Rails.root.join("private", "financial-actions-test-#{SecureRandom.hex(6)}.json")
    @input_path.dirname.mkpath
  end

  teardown do
    FileUtils.remove_file(@input_path) if @input_path.exist?
    %w[INPUT DRY_RUN JSON].each { |key| ENV.delete(key) }
    Rake::Task["budget:categorize"].reenable
  end

  test "categorize command emits structured JSON without writing in dry run" do
    original = create(:category, name: "Uncategorized")
    replacement = create(:category, name: "Household")
    transaction = create(:transaction, category: original)
    @input_path.write(JSON.generate(
      "mappings" => [ { "transaction_id" => transaction.id, "category" => replacement.id } ]
    ))
    ENV["INPUT"] = @input_path.to_s
    ENV["DRY_RUN"] = "1"
    ENV["JSON"] = "1"

    output, = capture_io { Rake::Task["budget:categorize"].invoke }
    parsed = JSON.parse(output)

    assert_equal 1, parsed.fetch("categorized")
    assert_equal 0, parsed.fetch("failed")
    assert_equal original, transaction.reload.category
  end
end
