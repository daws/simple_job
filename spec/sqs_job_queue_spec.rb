require 'spec_helper'

include SimpleJob

JobQueue.config[:logger].level = Logger::WARN

describe SQSJobQueue do

  before(:all) do
    AWS.config(:access_key_id => ENV['AWS_ACCESS_KEY_ID'], :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

    SimpleJob::SQSJobQueue.config :queue_prefix => 'simple-job'
    @normal_queue = SimpleJob::SQSJobQueue.define_queue 'normal', :default => true
    @high_priority_queue = SimpleJob::SQSJobQueue.define_queue 'high-priority', :visibility_timeout => 10
  end

  before(:each) do
    JobQueue.config :implementation => 'sqs'
    JobDefinition.job_definitions.clear

    @foo_sender_class = Class.new do
      @executions = []
      class << self
        attr_accessor :executions
        def name; 'FooSender'; end
      end
      include JobDefinition
      simple_job_attribute :target, :foo_content
      validates :target, :presence => true
      def execute
        self.class.executions << self
      end
      def ==(other)
        (target == other.target) && (foo_content == other.foo_content)
      end
    end
  end

  let(:normal_queue) { @normal_queue }
  let(:high_priority_queue) { @high_priority_queue }
  let(:foo_sender_class) { @foo_sender_class }

  context 'default queue' do

    subject { @normal_queue }

    it { should == JobQueue.default }
    it { should == JobQueue['normal'] }

    it 'should be able to complete a round trip of enqueue and poll' do
      polling_thread = Thread.new do
        subject.poll(:poll_interval => 0.5, :max_executions => 5)
      end

      foo = foo_sender_class.new(:target => 'joe', :foo_content => 'foo!')
      foo.enqueue
      polling_thread.join

      foo_sender_class.executions.should == [ foo ]
    end

  end

  context 'high priority queue' do

    subject { @high_priority_queue }
    
    it { should == JobQueue['high-priority'] }

  end

end
