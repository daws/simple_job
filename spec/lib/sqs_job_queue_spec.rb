# frozen_string_literal: true

RSpec.describe SimpleJob::SQSJobQueue do
  before do
    SimpleJob::SQSJobQueue.config(
      queue_prefix: 'simple-job',
      environment: 'test',
      cloud_watch_namespace: 'test'
    )
    SimpleJob::SQSJobQueue.queues = {}
    SimpleJob::SQSJobQueue.instance_variable_set(:@default_queue, nil)
  end

  describe '.default_queue', :vcr do
    let!(:queue) { SimpleJob::SQSJobQueue.define_queue('test', default: default) }

    context 'default_queue is defined' do
      let(:default) { true }

      it 'returns the default_queue' do
        expect(SimpleJob::SQSJobQueue.default_queue).to eq(queue)
      end
    end

    context 'default_queue is not defined' do
      let(:default) { false }

      it 'raises an error' do
        expect { SimpleJob::SQSJobQueue.default_queue }
          .to raise_error(StandardError, 'default queue not defined')
      end
    end
  end

  describe '.get_queue', :vcr do
    let!(:queue) { SimpleJob::SQSJobQueue.define_queue('test') }

    context 'when the queue is not found' do
      it 'raises an error' do
        expect { SimpleJob::SQSJobQueue.get_queue('testzzz') }
          .to raise_error(StandardError, 'queue with type testzzz not defined')
      end
    end

    context 'when the queue is found' do
      it 'returns the queue' do
        expect(SimpleJob::SQSJobQueue.get_queue('test')).to eq(queue)
      end
    end
  end

  describe 'with a defined queue' do
    let(:queue) do
      VCR.use_cassette('queue_create') do
        SimpleJob::SQSJobQueue.define_queue('test')
      end
    end

    it 'has the correct queue name' do
      expect(queue.instance_variable_get(:@queue_name)).to eq('simple-job-test-test')
    end

    describe '#poll' do
      let!(:job_definition) do
        Class.new do
          def self.name
            'TestJobDefinition'
          end
          include SimpleJob::JobDefinition

          simple_job_attribute :user_id

          def execute
            self.class.received_data << data
          end

          def self.received_data
            @received_data ||= []
          end
        end
      end

      let(:message_hash) do
        {
          'type' => 'test_job_definition',
          'version' => '1',
          'data' => { 'user_id' => 123 }
        }
      end
      let(:other_message_hash) do
        {
          'type' => 'test_job_definition',
          'version' => '1',
          'data' => { 'user_id' => 456 }
        }
      end

      it 'can process multiple messages', :vcr do
        queue.enqueue(JSON.dump(message_hash))
        queue.enqueue(JSON.dump(other_message_hash))

        queue.poll(poll_interval: 0, max_executions: 2)
        expect(job_definition.received_data)
          .to match_array([{ 'user_id' => 456 }, { 'user_id' => 123 }])
      end
    end
  end
end
