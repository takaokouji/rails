require File.expand_path('../../../../load_paths', __FILE__)

lib = File.expand_path("#{File.dirname(__FILE__)}/../../lib")
$:.unshift(lib) unless $:.include?('lib') || $:.include?(lib)

require 'config'

require 'test/unit'
require 'stringio'
require 'mocha'

require 'active_record'
require 'active_support/dependencies'
require 'connection'

begin
  require 'ruby-debug'
rescue LoadError
end

# Show backtraces for deprecated behavior for quicker cleanup.
ActiveSupport::Deprecation.debug = true

# Quote "type" if it's a reserved word for the current connection.
QUOTED_TYPE = ActiveRecord::Base.connection.quote_column_name('type')

def current_adapter?(*types)
  types.any? do |type|
    ActiveRecord::ConnectionAdapters.const_defined?(type) &&
      ActiveRecord::Base.connection.is_a?(ActiveRecord::ConnectionAdapters.const_get(type))
  end
end

ActiveRecord::Base.connection.class.class_eval do
  IGNORED_SQL = [/^PRAGMA/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /SHOW FIELDS/]

  def execute_with_query_record(sql, name = nil, &block)
    $queries_executed ||= []
    $queries_executed << sql unless IGNORED_SQL.any? { |r| sql =~ r }
    execute_without_query_record(sql, name, &block)
  end

  alias_method_chain :execute, :query_record
end

ActiveRecord::Base.connection.class.class_eval {
  attr_accessor :column_calls

  def columns_with_calls(*args)
    @column_calls ||= 0
    @column_calls += 1
    columns_without_calls(*args)
  end

  alias_method_chain :columns, :calls
}

unless ENV['FIXTURE_DEBUG']
  module ActiveRecord::TestFixtures::ClassMethods
    def try_to_load_dependency_with_silence(*args)
      ActiveRecord::Base.logger.silence { try_to_load_dependency_without_silence(*args)}
    end

    alias_method_chain :try_to_load_dependency, :silence
  end
end

require "cases/validations_repair_helper"
class ActiveSupport::TestCase
  include ActiveRecord::TestFixtures
  include ActiveRecord::ValidationsRepairHelper

  self.fixture_path = FIXTURES_ROOT
  self.use_instantiated_fixtures  = false
  self.use_transactional_fixtures = true

  def create_fixtures(*table_names, &block)
    Fixtures.create_fixtures(ActiveSupport::TestCase.fixture_path, table_names, {}, &block)
  end
end

# silence verbose schema loading
original_stdout = $stdout
$stdout = StringIO.new

begin
  adapter_name = ActiveRecord::Base.connection.adapter_name.downcase
  adapter_specific_schema_file = SCHEMA_ROOT + "/#{adapter_name}_specific_schema.rb"

  load SCHEMA_ROOT + "/schema.rb"

  if File.exists?(adapter_specific_schema_file)
    load adapter_specific_schema_file
  end
ensure
  $stdout = original_stdout
end
