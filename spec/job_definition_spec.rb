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

    it { should be_valid }

    it 'should have an execute method' do
      lambda { subject.execute }.should_not raise_error
    end

    it 'should default to a type of :bare_job' do
      subject.type.should == :bare_job
    end

    it 'should default to version "1"' do
      subject.version.should == '1'
    end

    it 'should default to single version "1"' do
      subject.versions.should == [ '1' ]
    end

    it 'should allow type to be overridden' do
      subject.class.register_simple_job :type => :alternate_type
      subject.type.should == :alternate_type
    end

    it 'should register its job definition' do
      JobDefinition.job_definitions.should == [ subject.class.definition ]
    end

    it 'should replace registered definition when calling register_simple_job' do
      subject.class.register_simple_job :type => :alternate, :versions => 3
      JobDefinition.job_definitions.size.should == 1
      JobDefinition.job_definitions.first[:type].should == :alternate
      JobDefinition.job_definitions.first.should == subject.class.definition
    end

    it 'should allow versions to be overridden' do
      subject.class.register_simple_job :versions => [ '23' ]
      subject.version.should == '23'
    end

    it 'should allow multiple versions' do
      subject.class.register_simple_job :versions => [ '3', '2', '1' ]
      subject.versions.should == [ '3', '2', '1' ]
      subject.version.should == '3'
    end

    it 'should allow version to be specified as a number' do
      subject.class.register_simple_job :versions => [ 3 ]
      subject.version.should == '3'
    end

    it 'should allow version to be specified without an array' do
      subject.class.register_simple_job :versions => 4
      subject.version.should == '4'
      subject.versions.should == [ '4' ]
    end

    it 'should add getters and setters for data attributes' do
      subject.class.simple_job_attribute :foo, :bar
      subject.should respond_to(:foo, :foo=, :bar, :bar=)
    end

    it 'should have a logger method on its class' do
      subject.class.should respond_to(:logger)
    end

    it 'should have a logger' do
      subject.should respond_to(:logger)
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

    it { should_not be_valid }

    it "should be valid once setting attr" do
      subject.attr = "foo"
      should be_valid
    end

    it "should produce valid json" do
      subject.attr = "foo"
      JSON.parse(subject.to_json).should == JSON.parse('{"data":{"attr":"foo"},"type":"simple_job","version":"1"}')
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
      JobDefinition.job_definitions.size.should == 3
    end

    it 'should return proper definition for each message' do
      JobDefinition.job_definition_class_for('foo', '1').should == @foo
      JobDefinition.job_definition_class_for('bar', '1').should == @legacy_bar
      JobDefinition.job_definition_class_for('bar', '2').should == @legacy_bar
      JobDefinition.job_definition_class_for('bar', '3').should == @bar
      JobDefinition.job_definition_class_for('foo', '2').should == nil
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
      JobDefinition.job_definition_class_for('foo_sender', '1').should == subject
    end

    it 'should match alternate name' do
      JobDefinition.job_definition_class_for('alternate_foo_sender', '1').should == subject
    end

    it 'should return default name for type' do
      subject.definition[:type].should == :foo_sender
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
      subject.class.max_attempt_count.should == 3
    end

  end

end
