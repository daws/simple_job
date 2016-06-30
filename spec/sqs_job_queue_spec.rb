require 'spec_helper'

require 'json'
require 'ostruct'

describe SimpleJob::SQSJobQueue do

  before(:all) do
    SimpleJob::SQSJobQueue.config queue_prefix: 'simple-job', environment: 'test'
    SimpleJob::JobQueue.config implementation: 'sqs'
  end

  before(:each) do
    allow(AWS::SQS).to receive(:new) { sqs }
    allow(Fog::AWS::CloudWatch).to receive(:new) { nil }
    SimpleJob::JobDefinition.job_definitions.clear
  end

  let(:sqs) { double('SQS', queues: sqs_queues) }
  let(:sqs_queues) do
    Class.new do
      def initialize(sqs_queue_class)
        @sqs_queue_class = sqs_queue_class
        @queues = {}
      end
      def create(name)
        @queues[name] ||= @sqs_queue_class.new
      end
    end.new(sqs_queue_class)
  end
  let(:sqs_queue_class) do
    Class.new do
      attr_reader :messages
      def initialize
        @messages = []
      end
      def send_message(message, options = {})
        @messages << message
      end
      def receive_messages(options = {})
        @messages.each do |message|
          yield(OpenStruct.new(body: message))
        end
        @messages.clear
      end
    end
  end

  let!(:normal_queue) { SimpleJob::SQSJobQueue.define_queue 'normal', default: true, accept_nested_definition: 'NotificationMetadata' }
  let!(:high_priority_queue) { SimpleJob::SQSJobQueue.define_queue 'high-priority', visibility_timeout: 10 }
  let!(:foo_sender_class) do
    Class.new do
      @executions = []
      class << self
        attr_accessor :executions
        def name; 'FooSender'; end
      end
      include JobDefinition
      simple_job_attribute :target, :foo_content
      validates :target, presence: true
      def execute
        self.class.executions << self
      end
      def ==(other)
        (target == other.target) && (foo_content == other.foo_content)
      end
    end
  end

  context 'default queue' do

    subject { normal_queue }

    it { is_expected.to eq(SimpleJob::JobQueue.default) }
    it { is_expected.to eq(SimpleJob::JobQueue['normal']) }

    it 'should be able to complete a round trip of enqueue and poll' do
      foo = foo_sender_class.new(target: 'joe', foo_content: 'foo!')
      foo.enqueue
      subject.poll(max_executions: 1)

      expect(foo_sender_class.executions).to eq([foo])
    end

  end

  context 'high priority queue' do

    subject { high_priority_queue }

    it { is_expected.to eq(SimpleJob::JobQueue['high-priority']) }

  end

  shared_examples 'a standard message' do |message|

    before(:each) do
      normal_queue.enqueue(message.to_json)
      normal_queue.poll(max_executions: 1)
    end

    it 'should execute FooSender' do
      expect(foo_sender_class.executions.size).to eq(1)
    end

  end

  context 'standard message' do

    it_should_behave_like 'a standard message', { type: 'foo_sender', version: '1' }

  end

  context 'message constructed by auto scaling' do

    it_should_behave_like 'a standard message',
      {
        AutoScalingGroupName: 'stash_website_production_1',
        NotificationMetadata: JSON.dump(type: 'foo_sender', version: '1')
      }

  end


end
