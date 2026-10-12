require "spec_helper"
require "activecube/graphql/lazy_query"

RSpec.describe Activecube::Graphql::LazyQuery do
  around do |example|
    saved = ENV['ACTIVECUBE_PARALLEL_FIELDS']
    example.run
  ensure
    ENV['ACTIVECUBE_PARALLEL_FIELDS'] = saved
    described_class.reset_max_parallel!
    described_class.instance_variable_set(:@semaphore, nil)
  end

  def configure(parallel)
    ENV['ACTIVECUBE_PARALLEL_FIELDS'] = parallel.to_s
    described_class.reset_max_parallel!
    described_class.instance_variable_set(:@semaphore, nil)
  end

  it "возвращает результат блока" do
    configure 4
    lazy = described_class.new { 42 }
    expect(lazy.value).to eq 42
  end

  it "запускает соседние запросы одновременно: время = max, а не сумма" do
    configure 4
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    a = described_class.new { sleep 0.3; :a }
    b = described_class.new { sleep 0.3; :b }
    expect([a.value, b.value]).to eq [:a, :b]
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(elapsed).to be < 0.5   # последовательно было бы >= 0.6
  end

  it "при выключенной параллельности считает синхронно в вызывающем потоке" do
    configure 1
    caller_thread = Thread.current
    seen = nil
    lazy = described_class.new { seen = Thread.current; :sync }
    expect(lazy.value).to eq :sync
    expect(seen).to equal caller_thread
  end

  it "сверх лимита деградирует к синхронному выполнению, а не падает" do
    configure 2
    gate = Queue.new
    holders = 2.times.map { described_class.new { gate.pop; :held } }
    sleep 0.05 # дать потокам занять оба разрешения
    seen = nil
    extra = described_class.new { seen = Thread.current; :extra }
    expect(extra.value).to eq :extra
    expect(seen).to equal Thread.current
    2.times { gate << :go }
    expect(holders.map(&:value)).to eq [:held, :held]
  end

  it "поднимает исключение из потока при форсировании, а не теряет его" do
    configure 4
    lazy = described_class.new { raise ArgumentError, "boom" }
    expect { lazy.value }.to raise_error(ArgumentError, "boom")
  end

  it "кэширует значение: блок выполняется один раз" do
    configure 4
    calls = 0
    lazy = described_class.new { calls += 1; :once }
    3.times { lazy.value }
    expect(calls).to eq 1
  end
end
