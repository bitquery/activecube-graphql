require "spec_helper"
require "activecube/graphql/thread_local_database"

RSpec.describe Activecube::Graphql::ThreadLocalDatabase do
  let(:query_methods) do
    Module.new do
      attr_reader :database
      def connected_to(database:) ; @database = database; yield; end
    end
  end
  let(:cube) { Class.new.tap { |c| c.extend(query_methods) } }

  before { described_class.install(cube) }

  it "returns the thread-local database inside with" do
    described_class.with(:litecoin) { expect(cube.database).to eq(:litecoin) }
  end

  it "falls back to the class attribute outside with" do
    cube.connected_to(database: :bitcoin) {}
    expect(cube.database).to eq(:bitcoin)
    described_class.with(:litecoin) { expect(cube.database).to eq(:litecoin) }
    expect(cube.database).to eq(:bitcoin)
  end

  it "keeps sibling threads apart" do
    seen = {}
    threads = { a: :litecoin, b: :bitcoin }.map do |k, db|
      Thread.new { described_class.with(db) { sleep 0.05; seen[k] = cube.database } }
    end
    threads.each(&:join)
    expect(seen).to eq(a: :litecoin, b: :bitcoin)
  end

  it "installs once" do
    described_class.install(cube)
    expect(cube.singleton_class.ancestors.count(described_class)).to eq(1)
  end
end
