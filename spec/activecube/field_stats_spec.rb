require "spec_helper"
require "activecube/graphql/field_stats"

RSpec.describe Activecube::Graphql::FieldStats do
  let(:stats) do
    Class.new do
      attr_accessor :session_id, :paths
      def initialize; @session_id = "gid"; @paths = [[:a]]; end
      def query_settings; { query_id: "qid", session_id: session_id }; end
    end.new
  end

  it "suffixes the shared session id" do
    expect(described_class.new(stats, "solana.asSender").session_id).to eq("gid:solana.asSender")
  end

  it "puts its own session id into query_settings and keeps the rest" do
    settings = described_class.new(stats, "x").query_settings
    expect(settings).to eq(query_id: "qid", session_id: "gid:x")
  end

  it "keeps an explicitly assigned session id and does not touch the shared one" do
    fs = described_class.new(stats, "x")
    fs.session_id = "coinpath123"
    expect(fs.session_id).to eq("coinpath123")
    expect(fs.query_settings[:session_id]).to eq("coinpath123")
    expect(stats.session_id).to eq("gid")
  end

  it "delegates everything else to the shared object" do
    fs = described_class.new(stats, "x")
    fs.paths = [[:b]]
    expect(stats.paths).to eq([[:b]])
  end
end
