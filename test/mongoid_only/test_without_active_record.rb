# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class TestMongoidOnlyWithoutActiveRecord < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_boots_without_active_record_and_does_not_auto_enable_mongoid_transactions
    output = run_probe(<<~'RUBY')
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

      puts({
        active_record: defined?(ActiveRecord),
        detected_adapter: Dex::Operation::TransactionAdapter.detect.inspect,
        result: op.new(name: "Ada").call
      }.inspect)
    RUBY

    assert_match(/active_record: nil/, output)
    assert_match(/detected_adapter: "nil"/, output)
    assert_match(/greeting: "hi Ada"/, output)
  end

  def test_explicit_mongoid_adapter_raises_load_error_when_mongoid_is_not_loaded
    output = run_probe(<<~RUBY)
      require "dexkit"

      op = Class.new(Dex::Operation) do
        transaction :mongoid

        def perform = :ok
      end

      begin
        op.new.call
      rescue LoadError, StandardError => e
        puts({ error_class: e.class.name, error_message: e.message }.inspect)
      end
    RUBY

    assert_match(/error_class: "LoadError"/, output)
    assert_match(/Mongoid is required for transactions/, output)
  end

  def test_async_operation_and_event_stringify_mongoid_ref_ids
    output = run_probe(<<~'RUBY')
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

      puts({
        serialized_class: serialized["user"].class.name,
        jobs: ActiveJob::Base.queue_adapter.enqueued_jobs.size,
        handler_name: handler_class.name.nil?
      }.inspect)
    RUBY

    assert_match(/serialized_class: "String"/, output)
    assert_match(/jobs: 1/, output)
  end

  def test_query_normalizes_mongoid_association_scopes_without_active_record
    output = run_probe(<<~'RUBY')
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

      puts({
        adapter: Dex::Query::Backend.adapter_for(ProbeParent.new.children).name,
        result_class: result.class.name
      }.inspect)
    RUBY

    assert_match(/Dex::Query::Backend::MongoidAdapter/, output)
    assert_match(/result_class: "Mongoid::Criteria"/, output)
  end

  def test_mongoid_uniqueness_and_locking_errors_are_prescriptive_without_active_record
    output = run_probe(<<~'RUBY')
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

        puts({
          form_ok: form_ok,
          first_clause_class: clauses.first[:email].class.name,
          clause_count: clauses.size,
          ref_error: ref_error,
          lock_error: lock_error
        }.inspect)
      ensure
        ProbeUser.singleton_class.send(:define_method, :where, original_where)
      end
    RUBY

    assert_match(/form_ok: true/, output)
    assert_match(/first_clause_class: "Regexp"/, output)
    assert_match(/clause_count: 2/, output)
    assert_match(/_Ref\(lock: true\) requires/, output)
    assert_match(/advisory_lock requires ActiveRecord/, output)
  end

  def test_rails_boots_with_mongoid_and_dex_without_active_record
    skip "Rails is unavailable in this bundle" unless rails_available?

    output = run_probe(<<~'RUBY')
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

      puts({
        active_record: defined?(ActiveRecord),
        railtie: defined?(Dex::Railtie),
        export_task: Rake::Task.task_defined?("dex:export"),
        guides_task: Rake::Task.task_defined?("dex:guides"),
        result: op.new.call
      }.inspect)
    RUBY

    assert_match(/active_record: nil/, output)
    assert_match(/railtie: "constant"/, output)
    assert_match(/export_task: true/, output)
    assert_match(/guides_task: true/, output)
    assert_match(/result: :ok/, output)
  end

  private

  def rails_available?
    return @rails_available if defined?(@rails_available)

    _, _, status = Open3.capture3("bundle", "exec", "ruby", "-e", 'require "rails"', chdir: ROOT)
    @rails_available = status.success?
  end

  def run_probe(code)
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-Ilib", "-e", code,
      chdir: ROOT
    )

    assert status.success?, "probe failed\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    stdout
  end
end
