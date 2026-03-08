# frozen_string_literal: true

require "test_helper"

class TestOperationRegistry < Minitest::Test
  def test_registry_returns_frozen_set
    result = Dex::Operation.registry
    assert_instance_of Set, result
    assert result.frozen?
  end

  def test_named_subclass_is_registered
    define_operation(:RegistryTestOp) { def perform = "ok" }
    assert_includes Dex::Operation.registry, RegistryTestOp
  end

  def test_anonymous_subclass_excluded
    op = build_operation { def perform = "ok" }
    refute_includes Dex::Operation.registry, op
  end

  def test_transitive_subclass_registered
    parent = define_operation(:RegistryParent2) { def perform = "ok" }
    Object.const_set(:RegistryChild2, Class.new(parent) { def perform = "child" })
    _tracked_constants[:operation] << :RegistryChild2

    assert_includes Dex::Operation.registry, RegistryParent2
    assert_includes Dex::Operation.registry, RegistryChild2
  end

  def test_deregister_removes_from_registry
    define_operation(:RegistryDeregTest) { def perform = "ok" }
    assert_includes Dex::Operation.registry, RegistryDeregTest
    Dex::Operation.deregister(RegistryDeregTest)
    refute_includes Dex::Operation.registry, RegistryDeregTest
  end

  def test_deregister_noop_for_unknown_class
    Dex::Operation.deregister(String)
  end

  def test_registry_is_a_snapshot
    define_operation(:RegistrySnapshotOp) { def perform = "ok" }
    snapshot = Dex::Operation.registry
    Dex::Operation.deregister(RegistrySnapshotOp)
    assert_includes snapshot, RegistrySnapshotOp
    refute_includes Dex::Operation.registry, RegistrySnapshotOp
  end

  def test_export_returns_array_of_hashes
    define_operation(:ExportTestOp) do
      prop :name, String
      def perform = name
    end
    result = Dex::Operation.export
    assert_instance_of Array, result
    entry = result.find { |h| h[:name] == "ExportTestOp" }
    assert entry
    assert_equal "ExportTestOp", entry[:name]
    assert entry.key?(:params)
  end

  def test_export_sorted_by_name
    define_operation(:ExportZzz) { def perform = "ok" }
    define_operation(:ExportAaa) { def perform = "ok" }
    result = Dex::Operation.export
    names = result.map { |h| h[:name] }
    aaa_idx = names.index("ExportAaa")
    zzz_idx = names.index("ExportZzz")
    assert aaa_idx < zzz_idx, "Expected ExportAaa before ExportZzz"
  end

  def test_export_json_schema_format
    define_operation(:ExportSchemaOp) do
      prop :name, String
      def perform = "ok"
    end
    result = Dex::Operation.export(format: :json_schema)
    entry = result.find { |h| h[:title] == "ExportSchemaOp" }
    assert entry
    assert_equal "https://json-schema.org/draft/2020-12/schema", entry[:$schema]
  end

  def test_export_unknown_format_raises
    assert_raises(ArgumentError) { Dex::Operation.export(format: :xml) }
  end

  def test_registry_excludes_stale_after_redefinition
    define_operation(:StaleTestOp) { def perform = "v1" }
    stale = StaleTestOp
    assert_includes Dex::Operation.registry, stale

    # Simulate reload: remove constant, redefine
    Object.send(:remove_const, :StaleTestOp)
    define_operation(:StaleTestOp) { def perform = "v2" }

    refute_includes Dex::Operation.registry, stale
    assert_includes Dex::Operation.registry, StaleTestOp
  end

  def test_clear_empties_registry
    define_operation(:ClearTestOp) { def perform = "ok" }
    assert_includes Dex::Operation.registry, ClearTestOp
    Dex::Operation.clear!
    refute_includes Dex::Operation.registry, ClearTestOp
  end
end
