# frozen_string_literal: true

require "test_helper"

class TestFormMongoidUniqueness < Minitest::Test
  MODEL_CONST = :MongoidUniquenessUser

  FakeQuery = Struct.new(:clauses) do
    def initialize
      super([])
    end

    def where(clause = nil)
      clauses << clause
      self
    end

    def exists?
      false
    end
  end

  def setup
    _configure_mongoid!

    Object.send(:remove_const, MODEL_CONST) if Object.const_defined?(MODEL_CONST)
    _silence_mongoid_warnings do
      Object.const_set(MODEL_CONST, Class.new do
        include Mongoid::Document

        field :email, type: String
      end)
    end
  end

  def teardown
    Object.send(:remove_const, MODEL_CONST) if Object.const_defined?(MODEL_CONST)
    super
  end

  def test_case_sensitive_false_uses_case_insensitive_regex_for_mongoid
    query = FakeQuery.new
    model_class = Object.const_get(MODEL_CONST)
    captured = nil

    model_class.stub :where, lambda { |clause|
      captured = clause
      query
    } do
      form_class = Class.new(Dex::Form) do
        model model_class
        attribute :email, :string
        validates :email, uniqueness: { case_sensitive: false }
      end

      assert form_class.new(email: "User@Example.com").valid?
    end

    matcher = captured[:email]
    assert_instance_of Regexp, matcher
    assert matcher.match?("user@example.com")
    assert matcher.match?("USER@example.com")
  end

  def test_persisted_mongoid_record_excludes_self_without_primary_key
    query = FakeQuery.new
    model_class = Object.const_get(MODEL_CONST)

    model_class.stub :where, ->(*) { query } do
      form_class = Class.new(Dex::Form) do
        model model_class
        attribute :email, :string
        validates :email, uniqueness: true
      end

      record = model_class.new(email: "user@example.com")
      record.define_singleton_method(:persisted?) { true }

      assert form_class.new(email: "user@example.com", record: record).valid?
    end

    assert_equal 1, query.clauses.size
    assert query.clauses.first.keys.first.to_s.include?("_id")
  end
end
