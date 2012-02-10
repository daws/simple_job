require 'active_model'
require 'active_support/inflector'

module SimpleJob
module JobDefinition

  RESERVED_ATTRIBUTES = [ :type, :version, :data ]

  def self.included(klass)

    klass.extend(ClassMethods)

    klass.class_eval do
      include ::ActiveModel::Validations
      include ::ActiveModel::Serializers::JSON
    end

    klass.include_root_in_json = false
    klass.register_simple_job

  end

  # should be overridden by including classes
  if !method_defined?(:execute)
    def execute
    end
  end

  def attributes
    {
      'type' => type,
      'version' => version,
      'data' => data,
    }
  end

  def attributes=(attributes)
    attributes.each do |key, value|
      send("#{key}=", value)
    end
  end

  def data
    @data ||= {}
    self.class.simple_job_attributes.each do |attribute|
      @data[attribute.to_s] ||= nil
    end
    @data
  end

  def data=(data)
    self.attributes = data
  end

  def type
    self.class.definition[:type]
  end

  def type=(type)
    if type.to_sym != self.type
      raise "tried to deserialize object with type #{type}, but this object only " +
        "supports type: #{self.type}"
    end
  end

  def versions
    self.class.definition[:versions]
  end

  def version
    versions.first
  end

  def version=(version)
    if !versions.include?(version.to_s)
      raise "tried to deserialize object with version #{version}, but this object " +
        "only supports versions: #{versions.join(", ")}"
    end
  end

  def enqueue(queue_type = nil)
    if valid?
      queue = (queue_type && JobQueue[queue_type]) || self.class.job_queue || JobQueue.default
      queue.enqueue(self.to_json)
    else
      false
    end
  end

  def enqueue!(queue_type = nil)
    enqueue(queue_type) || raise("object is not valid: #{errors.full_messages.join('; ')}")
  end

  def read_simple_job_attribute(attribute)
    data[attribute.to_s]
  end

  def write_simple_job_attribute(attribute, value)
    data[attribute.to_s] = value
  end

  def initialize(attributes = {})
    attributes.each do |key, value|
      send("#{key}=", value)
    end
  end

  def self.job_definition_class_for(type, version)
    @job_definitions.each do |definition|
      if (definition[:type] == type.to_sym) && (definition[:versions].include?(version))
        return definition[:class]
      end
    end
    nil
  end

  def self.job_definitions
    @job_definitions ||= []
  end

  private

  module ClassMethods

    def definition
      @definition
    end

    def register_simple_job(options = {})
      default_type = self.name.split('::').last.underscore.to_sym

      replace_existing = options.delete(:replace_existing) || false

      @definition = {
        :class => self,
        :type => default_type,
        :versions => [ '1' ],
      }.merge(options)

      @definition[:type] = @definition[:type].to_sym
      @definition[:versions] = Array(@definition[:versions])
      @definition[:versions].collect! { |value| value.to_s }

      if replace_existing
        ::SimpleJob::JobDefinition.job_definitions.delete_if { |item| item[:type] == default_type }
      end

      ::SimpleJob::JobDefinition.job_definitions << @definition
    end

    def job_queue(queue_type = nil)
      @job_queue = JobQueue[queue_type] if queue_type
      @job_queue
    end

    def simple_job_attributes
      @simple_job_attributes ||= []
    end

    def simple_job_attribute(*attributes)
      attributes.each do |attribute|
        attribute = attribute.to_sym

        if RESERVED_ATTRIBUTES.include?(attribute)
          raise "attempted to declare reserved attribute: #{attribute}"
        end

        simple_job_attributes << attribute

        class_eval <<-__EOF__
          def #{attribute}
            read_simple_job_attribute(:#{attribute})
          end

          def #{attribute}=(value)
            write_simple_job_attribute(:#{attribute}, value)
          end
        __EOF__
      end
    end

  end

end
end
