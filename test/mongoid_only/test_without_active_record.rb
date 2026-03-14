# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"

class TestMongoidOnlyWithoutActiveRecord < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  RESULT_MARKER = "__RESULT__"

  def setup
    skip "Probe tests disabled (set DEX_PROBE_TESTS=1)" unless ENV["DEX_PROBE_TESTS"] == "1"
  end

  def test_boots_without_active_record_and_does_not_auto_enable_mongoid_transactions
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "mongoid"
      require "active_job"

      ActiveJob::Base.queue_adapter = :test

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_#{Process.pid}"
        }
      end

      require "dexkit"

      class ProbeUser
        include Mongoid::Document
        field :name, type: String
      end

      op = Class.new(Dex::Operation) do
        prop :name, String
        transaction false

        def perform = { greeting: "hi #{name}" }
      end

      puts "__RESULT__#{JSON.generate(
        active_record: defined?(ActiveRecord),
        detected_adapter: Dex::Operation::TransactionAdapter.detect.inspect,
        result: op.new(name: "Ada").call
      )}"
    RUBY

    assert_nil result["active_record"]
    assert_equal "nil", result["detected_adapter"]
    assert_equal({ "greeting" => "hi Ada" }, result["result"])
  end

  def test_mongoid_transaction_adapter_is_no_longer_supported
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "dexkit"

      begin
        Class.new(Dex::Operation) do
          transaction :mongoid

          def perform = :ok
        end
      rescue ArgumentError => e
        puts "__RESULT__#{JSON.generate(error_class: e.class.name, error_message: e.message)}"
      end
    RUBY

    assert_equal "ArgumentError", result["error_class"]
    assert_match(/unknown transaction adapter/, result["error_message"])
  end

  def test_async_operation_and_event_stringify_mongoid_ref_ids
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "mongoid"
      require "active_job"

      ActiveJob::Base.queue_adapter = :test

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_#{Process.pid}"
        }
      end

      require "dexkit"

      class ProbeUser
        include Mongoid::Document
        field :name, type: String
      end

      operation_class = Class.new(Dex::Operation) do
        prop :user, _Ref(ProbeUser)

        def perform = nil
      end

      event_class = Class.new(Dex::Event) do
        prop :user, _Ref(ProbeUser)
      end

      handler_class = Class.new(Dex::Event::Handler) do
        on event_class

        def perform
        end
      end

      user = ProbeUser.new(name: "Ada")
      serialized = operation_class.new(user: user).async.send(:serialized_params)
      event_class.new(user: user).publish(sync: false)

      puts "__RESULT__#{JSON.generate(
        serialized_class: serialized["user"].class.name,
        jobs: ActiveJob::Base.queue_adapter.enqueued_jobs.size,
        handler_name: handler_class.name.nil?
      )}"
    RUBY

    assert_equal "String", result["serialized_class"]
    assert_equal 1, result["jobs"]
    assert_equal true, result["handler_name"]
  end

  def test_async_event_handlers_raise_prescriptive_load_error_without_active_job
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "mongoid"

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_#{Process.pid}"
        }
      end

      require "dexkit"

      event_class = Class.new(Dex::Event)

      Class.new(Dex::Event::Handler) do
        on event_class

        def perform
        end
      end

      begin
        event_class.new.publish(sync: false)
      rescue LoadError, StandardError => e
        puts "__RESULT__#{JSON.generate(error_class: e.class.name, error_message: e.message)}"
      end
    RUBY

    assert_equal "LoadError", result["error_class"]
    assert_match(/ActiveJob is required for async event handlers/, result["error_message"])
  end

  def test_query_normalizes_mongoid_association_scopes_without_active_record
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "mongoid"

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_#{Process.pid}"
        }
      end

      require "dexkit"

      class ProbeParent
        include Mongoid::Document
        has_many :children, class_name: "ProbeChild", inverse_of: :parent
      end

      class ProbeChild
        include Mongoid::Document
        field :name, type: String
        field :active, type: Mongoid::Boolean
        belongs_to :parent, class_name: "ProbeParent", inverse_of: :children, optional: true
      end

      query_class = Class.new(Dex::Query) do
        scope { ProbeParent.new.children }
        prop? :name, String
        filter :name, :contains
      end

      result = query_class.call(scope: ProbeChild.where(active: true), name: "al")

      puts "__RESULT__#{JSON.generate(
        adapter: Dex::Query::Backend.adapter_for(ProbeParent.new.children).name,
        result_class: result.class.name
      )}"
    RUBY

    assert_equal "Dex::Query::Backend::MongoidAdapter", result["adapter"]
    assert_equal "Mongoid::Criteria", result["result_class"]
  end

  def test_mongoid_uniqueness_and_locking_errors_are_prescriptive_without_active_record
    result = run_probe_json(<<~'RUBY')
      require "json"
      require "mongoid"

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_#{Process.pid}"
        }
      end

      require "dexkit"

      class ProbeUser
        include Mongoid::Document
        field :email, type: String
      end

      fake_query = Object.new
      clauses = []

      fake_query.define_singleton_method(:where) do |clause|
        clauses << clause
        self
      end

      fake_query.define_singleton_method(:exists?) { false }

      original_where = ProbeUser.method(:where)
      ProbeUser.singleton_class.send(:define_method, :where) do |clause|
        clauses << clause
        fake_query
      end

      begin
        form_class = Class.new(Dex::Form) do
          model ProbeUser
          attribute :email, :string
          validates :email, uniqueness: {case_sensitive: false}
        end

        record = ProbeUser.new(email: "User@example.com")
        record.define_singleton_method(:persisted?) { true }

        form_ok = form_class.new(email: "User@example.com", record: record).valid?

        begin
          Dex::RefType.new(ProbeUser, lock: true)
        rescue => e
          ref_error = "#{e.class}: #{e.message}"
        end

        begin
          op = Class.new(Dex::Operation) do
            advisory_lock :sync
            def perform = nil
          end
          op.new.call
        rescue LoadError, StandardError => e
          lock_error = "#{e.class}: #{e.message}"
        end

        puts "__RESULT__#{JSON.generate(
          form_ok: form_ok,
          first_clause_class: clauses.first[:email].class.name,
          clause_count: clauses.size,
          ref_error: ref_error,
          lock_error: lock_error
        )}"
      ensure
        ProbeUser.singleton_class.send(:define_method, :where, original_where)
      end
    RUBY

    assert_equal true, result["form_ok"]
    assert_equal "Regexp", result["first_clause_class"]
    assert_equal 2, result["clause_count"]
    assert_match(/_Ref\(lock: true\) requires/, result["ref_error"])
    assert_match(/advisory_lock requires ActiveRecord/, result["lock_error"])
  end

  def test_rails_boots_with_mongoid_and_dex_without_active_record
    skip "Rails is unavailable in this bundle" unless rails_available?

    result = run_probe_json(<<~'RUBY')
      require "json"
      require "fileutils"
      require "logger"
      require "rake"
      require "rails"
      require "active_job"
      require "mongoid"
      require "tmpdir"

      ActiveJob::Base.queue_adapter = :test

      APP_ROOT = Dir.mktmpdir("dexkit-rails-probe")
      at_exit { FileUtils.remove_entry(APP_ROOT) if Dir.exist?(APP_ROOT) }

      ProbeApp = Class.new(Rails::Application) do
        config.root = APP_ROOT
        config.eager_load = false
        config.secret_key_base = "x" * 64
        config.logger = Logger.new($stderr).tap { |logger| logger.level = Logger::FATAL }
      end

      Mongoid.configure do |config|
        config.clients.default = {
          hosts: ["127.0.0.1:27017"],
          database: "dexkit_probe_rails_#{Process.pid}"
        }
      end

      require "dexkit"

      ProbeApp.initialize!
      ProbeApp.load_tasks

      op = Class.new(Dex::Operation) do
        transaction false

        def perform = :ok
      end

      puts "__RESULT__#{JSON.generate(
        active_record: defined?(ActiveRecord),
        railtie: defined?(Dex::Railtie),
        export_task: Rake::Task.task_defined?("dex:export"),
        guides_task: Rake::Task.task_defined?("dex:guides"),
        result: op.new.call
      )}"
    RUBY

    assert_nil result["active_record"]
    assert_equal "constant", result["railtie"]
    assert_equal true, result["export_task"]
    assert_equal true, result["guides_task"]
    assert_equal "ok", result["result"]
  end

  private

  def rails_available?
    return @rails_available if defined?(@rails_available)

    _, _, status = Open3.capture3("bundle", "exec", "ruby", "-e", 'require "rails"', chdir: ROOT)
    @rails_available = status.success?
  end

  def run_probe_json(code)
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-Ilib", "-e", code,
      chdir: ROOT
    )

    assert status.success?, "probe failed\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    result_line = stdout.lines.reverse.find { |line| line.include?(RESULT_MARKER) }

    assert result_line, "probe did not emit a result marker\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"

    JSON.parse(result_line.split(RESULT_MARKER, 2).last)
  end
end
