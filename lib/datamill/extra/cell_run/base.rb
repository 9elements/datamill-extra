module Datamill
  module Extra
    module CellRun

# Represents a single run of a cell operated by a CellCulture.
class Base

  class << self
    # Adds a middleware to the stack for this cell run class.
    # Middlewares wrap around cell method invocations when the cell is being
    # operated upon, that is, when it is being invoked via some message from the reactor.
    # Invocations within an instance of the run class are not wrapped in middlewares.
    #
    # Middlewares are intended for things like exception tracing and
    # presenting a cell's compound persistent state in a nicer way.
    #
    # A middleware is a callable like this:
    # `->(run, method_name, args, callable) { ... callable.call; ... }` where
    # * `run` is the Run instance
    # * `method_name` is the invoked method as a String
    # * `args` is the arguments of the call
    # * `callable` takes no arguments and is used to recurse down the middleware stack.
    #
    # Alternatively, a symbol can be passed. In this case, the
    # corresponding cell run instance method which looks like this:
    # ```
    # def handle_something_around(method_name, args)
    #   # do something
    #   yield #recurse
    #   # do something
    # end
    # ```
    #
    # Midlewares are added in the order from the bottom (close to the reactor)
    # to the top (close to the invoked method) of the stack.
    def add_middleware(middleware)
      middleware_callables <<
        case middleware
        when Symbol
          ->(run, method_name, args, callable) { run.send(middleware, method_name, args, &callable) }
        else
          middleware.added(self) if middleware.respond_to?(:added)

          middleware
        end
    end

    def middleware_callables
      @middleware_callables ||= []
    end
  end

  def initialize(cell_state:, culture:)
    @cell_state = cell_state
    @culture = culture
  end

  attr_reader :cell_state, :culture

  def nop
    # default is to do nothing.
  end

  def persistent_data
    @cell_state.persistent_data
  end

  def persistent_data=(data)
    @cell_state.persistent_data = data
  end

  def cell_id
    @cell_state.id
  end

  def next_timeout=(timeout)
    @cell_state.next_timeout = timeout
  end

  def send_with_middlewares(method_name, *args)
    send_with_explicit_middlewares(
      self.class.middleware_callables.clone, method_name, *args)
  end

  private

  def send_with_explicit_middlewares(middlewares, method_name, *args)
    if middleware = middlewares.shift
      block = ->{ send_with_explicit_middlewares(middlewares, method_name, *args) }
      middleware.call(self, method_name, args, block)
    else
      send(method_name, *args)
    end
  end
end

    end
  end
end
