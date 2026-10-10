require "test_helper"
require "fileutils"
require "tmpdir"

class MonthlyProcessingOutputWriterTest < ActiveSupport::TestCase
  def setup
    @output_root = Pathname.new(Dir.mktmpdir("monthly-output")).realpath.join("output")
    @files = MonthlyProcessing::OutputWriter::FILENAMES.index_with { |name| "contents for #{name}\n" }
  end

  def teardown
    root = @output_root&.parent
    FileUtils.remove_entry(root) if root&.exist?
  end

  test "writer publishes a complete bundle atomically and refuses overwrite" do
    target = MonthlyProcessing::OutputWriter.call(
      output_root: @output_root,
      run_name: "run-00000001",
      files: @files
    )

    assert_equal MonthlyProcessing::OutputWriter::FILENAMES.sort, target.children.map { |path| path.basename.to_s }.sort
    assert_empty @output_root.join("runs").children.select { |path| path.basename.to_s.start_with?(".") }
    assert_raises(MonthlyProcessing::OutputWriter::WriteError) do
      MonthlyProcessing::OutputWriter.call(
        output_root: @output_root,
        run_name: "run-00000001",
        files: @files
      )
    end
    assert_equal "contents for process_run.json\n", target.join("process_run.json").binread
  end

  test "output symlink is rejected" do
    real_output = @output_root.parent.join("real-output")
    real_output.mkpath
    File.symlink(real_output, @output_root)

    assert_raises(MonthlyProcessing::PathSafety::UnsafePath) do
      MonthlyProcessing::OutputWriter.call(
        output_root: @output_root,
        run_name: "run-00000001",
        files: @files
      )
    end
  end
end
