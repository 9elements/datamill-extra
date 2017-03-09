require 'datamill/extra/cell_culture'

describe Datamill::Extra::CellCulture do
  let(:persistent_message_sink) { double "persistent message sink" }
  let(:ephemeral_message_sink) { double "ephemeral message sink" }

  let(:run_assertion_double) { double "run assertion double" }
  let(:culture_assertion_double) { double "culture assertion double" }

  let(:implementation) do
    Class.new(described_class) do
      describe_cell do
        add_middleware ->(run, method_name, args, callable) {
          run.assertion_double.before_bottom(run, method_name, args)
          callable.call
          run.assertion_double.after_bottom(run, method_name, args)
        }
        add_middleware :top_around

        def nop
          assertion_double.nop(self)
        end

        def handle_timeout
          assertion_double.handle_timeout(self)
        end

        def frobnicate(*args)
          assertion_double.frobnicate(self, *args)
        end

        def top_around(method_name, args)
          assertion_double.before_top(self, method_name, args)
          yield
          assertion_double.after_top(self, method_name, args)
        end

        def assertion_double; culture.run_assertion_double end
      end

      # ...also demonstrating cultures can be initialized with dependencies!
      def initialize(
          culture_assertion_double:, run_assertion_double:,
          persistent_message_sink:, ephemeral_message_sink:)
        @run_assertion_double = run_assertion_double
        @assertion_double = culture_assertion_double
        @persistent_message_sink = persistent_message_sink
        @ephemeral_message_sink = ephemeral_message_sink
      end
      attr_reader :run_assertion_double

      # Here we override static behaviour instead of making it injectable ;)
      def wrap_behaviour_message_for_reactor_handler(cell_id:, cell_message:)
        @assertion_double.wrap_behaviour_message_for_reactor_handler(
          cell_id: cell_id, cell_message: cell_message)
      end

      # Culture needs to implement (when persistent messaging is being used):
      def persistent_message_sink
        @persistent_message_sink
      end

      # Culture needs to implement (when ephemeral messaging is being used):
      def ephemeral_message_sink
        @ephemeral_message_sink
      end

      def do_something_with_cell(id_part_1, id_part_2, payload)
        proxy.for_cell(id_part_1, id_part_2).frobnicate(payload)
      end

      def do_something_with_cell_ephemeral(id_part_1, id_part_2, payload)
        proxy(ephemeral: true).for_cell(id_part_1, id_part_2).frobnicate(payload)
      end

      # demonstrate conversion of custom `.for_cell` arguments
      def cell_id(id_part_1, id_part_2)
        [id_part_1, id_part_2].join
      end
    end
  end

  subject do
    implementation.new(
      culture_assertion_double: culture_assertion_double,
      run_assertion_double: run_assertion_double,
      persistent_message_sink: persistent_message_sink,
      ephemeral_message_sink: ephemeral_message_sink
    )
  end

  let(:custom_cell_identifier) { ["foo", "bar"] }

  describe "sending a cell message" do
    let(:payload) { ["payload"] }

    shared_examples_for "wrapping a proxied message and being able to deliver it" do
      it "captures a proxy method invocation and delivers it, wrapped in middlewares" do
        cell_message =
          expect_sink_to_receive_message(sink, *custom_cell_identifier) do
            invoke_proxy
          end

        cell_state = build_cell_state(cell_id(*custom_cell_identifier))

        expecting_ordered_run_middleware_invocations("frobnicate", payload) do
          expect(run_assertion_double).to receive(:frobnicate) do |run, *args|
            expect_run_to_be_set_up_properly(run, cell_state)
            expect(args).to eql(payload)
          end.ordered
        end
        subject.behaviour.handle_message(cell_state, cell_message)
      end

      def expect_sink_to_receive_message(sink, *cell_identification)
        message_in_sink = nil

        allow(culture_assertion_double).to receive(:wrap_behaviour_message_for_reactor_handler) do
              |cell_id:, cell_message:|

          expect(cell_id).to eql(cell_id(*custom_cell_identifier))

          { cell_id: cell_id, cell_message: cell_message }
        end

        expect(sink).to receive(:call) do |message|
          message_in_sink = message[:cell_message]
        end

        expect { yield }.to change { message_in_sink }

        return message_in_sink
      end
    end

    context "with the persistent message sink" do
      let(:sink) do
        persistent_message_sink
      end

      it_behaves_like "wrapping a proxied message and being able to deliver it" do
        def invoke_proxy
          subject.do_something_with_cell(*custom_cell_identifier, *payload)
        end
      end
    end

    context "with the ephemeral message sink" do
      let(:sink) do
        ephemeral_message_sink
      end

      it_behaves_like "wrapping a proxied message and being able to deliver it" do
        def invoke_proxy
          subject.do_something_with_cell_ephemeral(*custom_cell_identifier, *payload)
        end
      end
    end
  end

  describe "delegation of behaviour messages" do
    it "delegates `#nop` to a cell run, wrapped in middlewares" do
      cell_state = build_cell_state(cell_id(*custom_cell_identifier))

      expecting_ordered_run_middleware_invocations("nop") do
        expect(run_assertion_double).to receive(:nop) do |run|
          expect_run_to_be_set_up_properly(run, cell_state)
        end.ordered
      end

      subject.behaviour.nop(cell_state)
    end

    it "delegates `#handle_timeout` to a cell run, wrapped in middlewares" do
      cell_state = build_cell_state(cell_id(*custom_cell_identifier))

      expecting_ordered_run_middleware_invocations("handle_timeout") do
        expect(run_assertion_double).to receive(:handle_timeout) do |run|
          expect_run_to_be_set_up_properly(run, cell_state)
        end.ordered
      end

      subject.behaviour.handle_timeout(cell_state)
    end
  end

  def expecting_ordered_run_middleware_invocations(method_name, expected_args = [])
    args_asserter = Proc.new do |run, method_name_arg, args|
      # run is an instance of the culture's cell run class:
      expect(run.culture).to be(subject)
      expect(run).to respond_to(:frobnicate)

      expect(args).to eql(expected_args)
      expect(method_name_arg).to be_a(String)
      expect(method_name_arg).to eql(method_name)
    end

    expect(run_assertion_double).to receive(:before_bottom).ordered(&args_asserter)
    expect(run_assertion_double).to receive(:before_top).ordered(&args_asserter)
    yield
    expect(run_assertion_double).to receive(:after_top).ordered(&args_asserter)
    expect(run_assertion_double).to receive(:after_bottom).ordered(&args_asserter)
  end

  def expect_run_to_be_set_up_properly(run, cell_state)
    expect(run.cell_state).to equal(cell_state)

    expect(run.persistent_data).to eql(cell_state.persistent_data)
    expect {
      run.persistent_data = "different value"
    }.to change {
      cell_state.persistent_data
    }

    expect {
      run.next_timeout = Time.now
    }.to change {
      cell_state.next_timeout
    }
  end

  def cell_id(*cell_identification)
    subject.cell_id(*custom_cell_identifier)
  end

  def build_cell_state(cell_id)
    persistent_data = "dummy persistent data"

    Datamill::Cell::State.new(
      behaviour: subject.behaviour,
      persistent_data: persistent_data,
      id: cell_id
    )
  end
end

