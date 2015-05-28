require 'spec_helper'

include SimpleJob

describe JobDefinition do

  context 'a bare class including JobDefinition' do

    before(:each) do
      JobDefinition.job_definitions.clear
      @bare_job = Class.new do
        def self.name; 'BareJob'; end
        include JobDefinition
      end
    end

    subject { @bare_job.new }

    it { is_expected.to be_valid }

    it 'should have an execute method' do
      expect { subject.execute }.not_to raise_error
    end

    it 'should default to a type of :bare_job' do
      expect(subject.type).to eq(:bare_job)
    end

    it 'should default to version "1"' do
      expect(subject.version).to eq('1')
    end

    it 'should default to single version "1"' do
      expect(subject.versions).to eq([ '1' ])
    end

    it 'should allow type to be overridden' do
      subject.class.register_simple_job :type => :alternate_type
      expect(subject.type).to eq(:alternate_type)
    end

    it 'should register its job definition' do
      expect(JobDefinition.job_definitions).to eq([ subject.class.definition ])
    end

    it 'should replace registered definition when calling register_simple_job' do
      subject.class.register_simple_job :type => :alternate, :versions => 3
      expect(JobDefinition.job_definitions.size).to eq(1)
      expect(JobDefinition.job_definitions.first[:type]).to eq(:alternate)
      expect(JobDefinition.job_definitions.first).to eq(subject.class.definition)
    end

    it 'should allow versions to be overridden' do
      subject.class.register_simple_job :versions => [ '23' ]
      expect(subject.version).to eq('23')
    end

    it 'should allow multiple versions' do
      subject.class.register_simple_job :versions => [ '3', '2', '1' ]
      expect(subject.versions).to eq([ '3', '2', '1' ])
      expect(subject.version).to eq('3')
    end

    it 'should allow version to be specified as a number' do
      subject.class.register_simple_job :versions => [ 3 ]
      expect(subject.version).to eq('3')
    end

    it 'should allow version to be specified without an array' do
      subject.class.register_simple_job :versions => 4
      expect(subject.version).to eq('4')
      expect(subject.versions).to eq([ '4' ])
    end

    it 'should add getters and setters for data attributes' do
      subject.class.simple_job_attribute :foo, :bar
      is_expected.to respond_to(:foo, :foo=, :bar, :bar=)
    end

    it 'should have a logger method on its class' do
      expect(subject.class).to respond_to(:logger)
    end

    it 'should have a logger' do
      is_expected.to respond_to(:logger)
    end

  end

  context 'a simple class including JobDefinition' do

    subject {
      simple_job = Class.new do
        def self.name; 'SimpleJob'; end
        include JobDefinition
        simple_job_attribute :attr
        validates :attr, :presence => true
      end
      simple_job.new
    }

    it { is_expected.not_to be_valid }

    it "should be valid once setting attr" do
      subject.attr = "foo"
      is_expected.to be_valid
    end

    it "should produce valid json" do
      subject.attr = "foo"
      expect(JSON.parse(subject.to_json)).to eq(JSON.parse('{"data":{"attr":"foo"},"type":"simple_job","version":"1"}'))
    end

  end

  context 'an environment with three JobDefinition classes' do

    before(:each) do
      job_tracker = Class.new do
        class << self; attr_accessor :executions; end
        def execute
          self.class.executions = (self.class.executions || 0) + 1
        end
      end

      JobDefinition.job_definitions.clear

      @foo = Class.new(job_tracker) do
        def self.name; 'Foo'; end
        include JobDefinition
      end

      @bar = Class.new(job_tracker) do
        def self.name; 'Bar'; end
        include JobDefinition
        register_simple_job :versions => 3
      end

      @legacy_bar = Class.new(job_tracker) do
        def self.name; 'LegacyBar'; end
        include JobDefinition
        register_simple_job :type => 'bar', :versions => [ 2, 1 ]
      end
    end

    it 'should have three registered job definitions' do
      expect(JobDefinition.job_definitions.size).to eq(3)
    end

    it 'should return proper definition for each message' do
      expect(JobDefinition.job_definition_class_for('foo', '1')).to eq(@foo)
      expect(JobDefinition.job_definition_class_for('bar', '1')).to eq(@legacy_bar)
      expect(JobDefinition.job_definition_class_for('bar', '2')).to eq(@legacy_bar)
      expect(JobDefinition.job_definition_class_for('bar', '3')).to eq(@bar)
      expect(JobDefinition.job_definition_class_for('foo', '2')).to eq(nil)
    end

  end

  context 'a job definition that registers an alternate type name' do

    before(:each) do
      JobDefinition.job_definitions.clear

      @foo_sender_class = Class.new do
        class << self
          def name; 'FooSender'; end
        end
        include JobDefinition
        register_simple_job :type => 'alternate_foo_sender', :replace_existing => false
      end
    end

    subject { @foo_sender_class }

    it 'should match default name' do
      expect(JobDefinition.job_definition_class_for('foo_sender', '1')).to eq(subject)
    end

    it 'should match alternate name' do
      expect(JobDefinition.job_definition_class_for('alternate_foo_sender', '1')).to eq(subject)
    end

    it 'should return default name for type' do
      expect(subject.definition[:type]).to eq(:foo_sender)
    end

  end

  context 'a job definition instance that declares a max attempt count' do

    before(:each) do
      JobDefinition.job_definitions.clear

      @foo_sender_class = Class.new do
        class << self
          def name; 'FooSender'; end
        end
        include JobDefinition
        max_attempt_count 3
      end
    end

    subject { @foo_sender_class.new }

    it 'should store the max attempt count' do
      expect(subject.class.max_attempt_count).to eq(3)
    end

  end

end
