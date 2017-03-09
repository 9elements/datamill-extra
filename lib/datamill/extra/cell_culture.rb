require 'datamill/extra/cell_run/base'
require 'datamill/reactor/cell_handler'

module Datamill
  module Extra

# Acts as a communication proxy for one kind of cell.
# The kind of cell is modelled as a class (see `.describe_cell`)
# and invocations of the cell ("cell runs") as instances of this class.
class CellCulture

  class << self
    # Provide an implementation for a cell run by passing a block!
    def describe_cell
      @cell_run_class = Class.new(CellRun::Base, &Proc.new)
      const_set "CellRun", @cell_run_class # nice for debugging
      return @cell_run_class
    end
    attr_reader :cell_run_class
  end

  # The behaviour, implementing the API toward the reactor
  def behaviour
    @behaviour ||= Behaviour.new(name_base: self.class.to_s, cell_run_factory: method(:cell_run))
  end

  def wrap_behaviour_message_for_reactor_handler(cell_id:, cell_message:)
    Datamill::Reactor::CellHandler.build_message_to_cell(
      behaviour: behaviour,
      id: cell_id,
      cell_message: cell_message)
  end

  private

  # Converts `.proxy.for_cell` arguments to a cell id
  def cell_id(*args)
    # When desired, cell proxies can be build with arbitrary arguments in
    # place of the cell id. Override this method to implement conversion
    # from such arguments to a cell id, which must be a string.
    raise ArgumentError unless args.lenth == 1 && args.first.is_a?(String)

    cell_id = args.first
    return cell_id
  end

  # returns the persistent message queue of the reactor, as a simple callable
  def persistent_message_sink
    raise NotImplementedError # must be overridden
  end

  # returns the reactor's sink for ephemeral messages, as a simpe callable
  def ephemeral_message_sink
    raise NotImplementedError # must be overridden
  end

  def proxy(ephemeral: false)
    @proxy_factories ||= Hash.new do |hash, key|
      sink =
        if key
          ephemeral_message_sink
        else
          persistent_message_sink
        end

      hash[key] = ProxyFactory.new(
        method(:wrap_behaviour_message_for_reactor_handler),
        sink,
        method(:cell_id)
      )
    end
    @proxy_factories[ephemeral]
  end

  def cell_run(cell_state)
    # TODO check configuration has happened
    self.class.cell_run_class.new(cell_state: cell_state, culture: self)
  end

  class Behaviour
    def initialize(name_base:, cell_run_factory:)
      @cell_run_factory = cell_run_factory

      raise ArgumentError if name_base.empty?
      @behaviour_name = "#{name_base}=Behaviour"
    end
    attr_reader :behaviour_name

    def nop(cell_state)
      CellInteractor.call_method(
        receiver: @cell_run_factory.call(cell_state),
        method_name: "nop",
        args: []
      )
    end

    def handle_message(cell_state, message)
      CellInteractor.deliver_packed_invocation(
        receiver: @cell_run_factory.call(cell_state),
        packed_invocation: message
      )
    end

    def handle_timeout(cell_state)
      CellInteractor.call_method(
        receiver: @cell_run_factory.call(cell_state),
        method_name: "handle_timeout",
        args: []
      )
    end
  end

  class ProxyFactory
    def initialize(message_wrapper, sink, cell_id_converter)
      @sink = sink
      @message_wrapper = message_wrapper
      @cell_id_converter = cell_id_converter
    end

    def for_cell(*cell_id_arguments)
      cell_id = @cell_id_converter.call(*cell_id_arguments)
      Proxy.new(@message_wrapper, cell_id, @sink)
    end
  end

  class Proxy
    def initialize(message_wrapper, cell_id, sink)
      @wrapper = message_wrapper
      @cell_id = cell_id
      @sink = sink
    end

    def method_missing(method_name, *args)
      packed_method = CellInteractor.pack_invocation(method_name: method_name, args: args)
      message = @wrapper.call(cell_id: @cell_id, cell_message: packed_method)
      @sink.call(message)
    end
  end

  module CellInteractor
    # Defines how a message for a cell is packed into a behaviour message,
    # and how such a message is unpacked and delivered.
    # Also handles interacting with the other cell run endpoints, so
    # middlewares are properly invoked.

    def self.pack_invocation(method_name:, args:)
      [method_name.to_s, args]
    end

    def self.call_method(receiver:, method_name:, args:)
      receiver.send_with_middlewares(method_name, *args)
    end

    def self.deliver_packed_invocation(receiver:, packed_invocation:)
      method_name, args = packed_invocation

      receiver.send_with_middlewares(method_name, *args)
    end
  end
end

  end
end

