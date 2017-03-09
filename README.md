# Datamill::Extra

This gem contains things related to the datamill gem which have not proven to be
useful or stable enough to go into the main gem.

## Cell cultures and cell runs

Recall these datamill concepts first:

A "behaviour" is an implementation of how cells of a certain kind need to be
operated. For Datamill, a Behaviour is just an object that implements the
`Datamill::Cell::Behaviour` interface.

Behaviours implement functions managing the cell's `State`, which
encapsulates all the state of and information about the cell, and contains no behaviour
of itself. The behaviour functions themselves are stateless.

This is a rather functional approach and not always nice to operate with.
To give this a more object-oriented flavour,
you can implement a *cell culture* using `Datamill::Extra::CellCulture`.

A cell culture provides the behaviour object, the interface toward the reactor, for
you. Inside the cell culture you describe what a *cell run* looks like,
a class instantiated by the behaviour to handle a single invocation
for the cell. On this cell run you can implement general handling
around all method calls (like logging, exception handling,
presenting a cell's id in a more suitable way...) as well as respond
to cell messages.

## Model events

Model events allow for hooking into the lifecycle events of classic ORMs
to emit Events. These events are managed by corresponding `Datamill::Event` subclasses.
