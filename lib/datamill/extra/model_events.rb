module Datamill
  module Extra

# Hooks into a model class to register callback handlers emitting
# `Datamill::Event`s. Also acts as a hash for known event classes,
# for easy enumeration.
class ModelEvents < Hash
  def initialize(model)
    @model = model

    # defaults
    @event_attribute_names = [:id]
    @event_attributes_filler = ->(record, event) { event.id = record.id.to_s }
    @before_destroy_effective_callable = Proc.new {}
  end

  # Yields with the record. Abstracts away the details of transactionfull/~less
  # callback handling.
  def before_destroy_effective
    @before_destroy_effective_callable = Proc.new
  end
  attr_reader :before_destroy_effective_callable

  def queue_to(queue)
    @queue = queue
  end

  def attributes(*attributes)
    @event_attribute_names = attributes
    @event_attributes_filler = Proc.new
  end
  attr_reader :event_attribute_names

  attr_reader :queue, :model

  def callbacks
    @callbacks ||= callbacks_class.new(self, @event_attribute_names)
  end

  def publish(record, event_key)
    event = fetch(event_key).new
    @event_attributes_filler.call(record, event)
    queue.push event
  end

  def self.attach_to(model)
    if model.is_a?(ModelMethods)
      raise ArgumentError, "this method can only be called once on each model"
    end
    model.send :extend, ModelMethods

    events = model.datamill_model_events = new(model)
    yield events

    events.callbacks.generate_event_cases!
    events.callbacks.hook!
    events.freeze
  end

  module ModelMethods
    attr_accessor :datamill_model_events
  end

  class Callbacks
    def initialize(events, event_attribute_names)
      @events = events
      @event_attribute_names = event_attribute_names
    end
    attr_reader :events

    def model; events.model; end

    def build_event_case(name_segment)
      datamill_event_name = "Datamill#{name_segment}"
      event_attribute_names = @event_attribute_names

      Class.new(Datamill::Event) do
        class << self
          attr_reader :event_name
        end
        @event_name = datamill_event_name

        attributes(*event_attribute_names)
      end
    end
  end

  class TransactionlessCallbacks < Callbacks
    def generate_event_cases!
      events["saved"] = build_event_case("#{model}Saved")
      events["destroyed"] = build_event_case("#{model}Destroyed")
    end

    def hook!
      model.after_save do
        model_events = self.class.datamill_model_events
        model_events.publish(self, "saved")
        true
      end

      model.before_destroy do
        model_events = self.class.datamill_model_events
        model_events.before_destroy_effective_callable.call(self)
        true
      end

      model.after_destroy do
        model_events = self.class.datamill_model_events
        model_events.publish(self, "destroyed")
        true
      end
    end
  end

  private

  def callbacks_class
    if model.respond_to?(:after_commit)
      raise NotImplementedError
    else
      TransactionlessCallbacks
    end
  end
end

  end
end

