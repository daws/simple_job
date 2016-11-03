require 'singleton'

include SimpleJob

RSpec.describe JobQueue do

  before(:each) do
    @array_queue_class = Class.new(JobQueue) do
      def self.name; 'ArrayQueue'; end
      register_job_queue 'array', self

      include Singleton
      def self.default_queue
        instance
      end

      def self.get_queue(type, options = {})
        instance
      end
      def queue
        @queue ||= []
      end
      def enqueue(message, options = {})
        queue << message
      end
      def poll(options = {}, &block)
        options = {
          :interval => 0.001
        }.merge(options)
        loop do
          message = queue.shift
          yield(message) if message
          Kernel.sleep(options[:interval])
        end
      end
    end

    JobDefinition.job_definitions.clear
    @bare_job_class = Class.new do
      def self.name; 'BareJob'; end
      include JobDefinition
    end

    JobQueue.config :implementation => 'array'
  end

  subject { @array_queue_class }

  let(:bare_job_class) { @bare_job_class }

  it 'should default to configured queue class' do
    expect(JobQueue.queue_class).to eq(subject)
  end

  it 'should return queue using array operator' do
    expect(JobQueue['sometype']).to eq(subject.instance)
  end

  it 'should return default queue' do
    expect(JobQueue.default).to eq(subject.instance)
  end

  it 'should enqueue a JSON message when job enqueue method is called' do
    job = bare_job_class.new
    expect { job.enqueue }.to change { subject.instance.queue.size }.from(0).to(1)
    expect(JSON.parse(subject.instance.queue[0])).to eq({ 'type' => 'bare_job', 'version' => '1', 'data' => {} })
  end

  it 'should retrieve all messages when polling' do
    retrieved_messages = 0

    polling_thread = Thread.new do
      subject.instance.poll do |message|
        retrieved_messages += 1
      end
    end

    20.times { bare_job_class.new.enqueue }

    Kernel.sleep(0.1)
    polling_thread.kill

    expect(retrieved_messages).to eq(20)
  end

end
