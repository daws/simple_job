module SimpleJob
class TestJobQueue < JobQueue

  register_job_queue 'test', self

  def self.default_queue
    get_queue('default')
  end

  def self.get_queue(type, options = {})
    queues[type] ||= TestJobQueue.new(type)
  end

  def self.queues
    @queues ||= {}
  end

  def self.clear!
    queues.each_value do |queue|
      queue.clear!
    end
  end

  def self.jobs(type = 'default')
    get_queue(type).jobs
  end

  def initialize(type)
    @type = type
    @jobs = []
  end

  def clear!
    @jobs.clear
  end

  def enqueue(message, options = {})
    hash = JSON.parse(message)
    job_type = hash['type']
    definition_class = JobDefinition.job_definition_class_for(job_type, hash['version'])
    job = definition_class.new.from_json(message)
    @jobs << job
  end

  def poll(options = {}, &block)
    raise NotImplementedError
  end

  def jobs
    @jobs.dup
  end

end
end
