require "test_helper"

class MonthlyProcessing::PathSafetyTest < ActiveSupport::TestCase
  setup do
    @private_root = Rails.root.join("private")
    @private_root.mkpath
    @private_file = @private_root.join("path-safety-#{SecureRandom.hex(6)}.csv")
    @private_file.write("header\nvalue\n")
    @outside_root = Pathname.new(Dir.mktmpdir("path-safety-outside"))
    @outside_file = @outside_root.join("outside.csv")
    @outside_file.write("outside\n")
    @private_link = @private_root.join("path-safety-link-#{SecureRandom.hex(6)}")
    File.symlink(@outside_root, @private_link)
  end

  teardown do
    FileUtils.remove_file(@private_file) if @private_file&.exist?
    FileUtils.remove_entry(@private_link) if @private_link&.exist? || @private_link&.symlink?
    FileUtils.remove_entry(@outside_root) if @outside_root&.exist?
  end

  test "allows a repo-contained file below private" do
    assert_equal @private_file.realpath, MonthlyProcessing::PathSafety.source_file(@private_file).realpath
    assert_equal @private_file.realpath, MonthlyProcessing::PathSafety.source_file(@private_file.relative_path_from(Rails.root)).realpath
  end

  test "rejects another repo-contained source file" do
    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) do
      MonthlyProcessing::PathSafety.source_file(Rails.root.join("README.md"))
    end
  end

  test "rejects a private path that escapes through an intermediate symlink" do
    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) do
      MonthlyProcessing::PathSafety.source_file(@private_link.join("outside.csv"))
    end
  end
end
