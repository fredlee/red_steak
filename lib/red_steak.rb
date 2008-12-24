# require 'debug'

# An extensible, instantiable, cloneable statemachine.
#
module RedSteak
  class UnknownTransitionError < Exception; end
  class InvalidTransitionError < Exception; end
  class CannotTransitionError < Exception; end
  class AmbigousTransitionError < Exception; end

  class Base 
    attr_accessor :name
    attr_reader :_proto
    attr_reader :_options

    def initialize opts = EMPTY_HASH
      @name = nil
      @_proto = nil
      @_options = _dup_opts opts
      @_options.each do | k, v |
        s = "#{k}="
        if respond_to? s
          # $stderr.puts "#{self.class} #{self.object_id} s = #{s.inspect}, v = #{v.inspect}"
          send s, v
          @_options.delete k
        end
      end
      @_proto ||= self
    end

    def name= x
      @name = x && x.to_sym
      x
    end

    def _dup_opts opts
      h = { }
      opts.each do | k, v |
        k = k.to_sym
        case v
        when String, Array, Hash
          v = v.dup
        end
        h[k] = v
      end
      h
    end

    def dup
      x = super
      x.dup_deepen!
      x
    end

    def dup_deepen!
      @_options = _dup_opts @_options
    end

    def to_s
      name.to_s
    end

    def inspect
      "#<#{self.class} #{self.name.inspect}>"
    end

    # Called by subclasses to notify/query the context for specific actions.
    def _notify! action, args, sm = nil
      method = _options[action] || action
      # $stderr.puts "  _notify #{self.inspect} #{action.inspect} method = #{method.inspect}"
      c ||= (sm || self).context
      # $stderr.puts "    c = #{c.inspect}"
      if c
        case
        when Symbol === method && (c.respond_to?(method))
          c.send(method, self, *args)
        when Proc === method
          method.call(self, *args)
        else
          nil
        end
      else
        nil
      end
    end


    def method_missing sel, *args, &blk
      $stderr.puts "#{self}#method_missing #{sel.inspect} #{args}"
      cntx = statemachine.context
      if cntx
        return cntx.send(sel, *args, &blk)
      end
      $stderr.puts "  #{caller.join("\n  ")}"
      super
    end

  end # class


  # A Statemachine object.
  class Statemachine < Base
    # The list of all states.
    attr_reader :states

    # The list of all transitions.
    attr_reader :transitions

    # The superstate if this is a substatemachine.
    attr_accessor :superstate

    # The start state.
    attr_accessor :start_state

    # The end state.
    attr_accessor :end_state

    # The current state.
    attr_reader :state
    
    # The receiver of all methods missing inside Statemachine, State, and Transition.
    attr_accessor :context

    # If true.
    attr_accessor :verbose

    # History of all transitions.
    attr_accessor :history

    attr_accessor :logger


    def initialize opts
      super
      @state = nil
      @start_state = nil
      @end_state = nil
      @states = [ ]
      @transitions = [ ]
      @history = [ ]
      @verbose ||= 0
    end
    

    # Sets the start state.
    def start_state= x
      @start_state = x
      if x
        @states.each do | s |
          s.state_type = nil if s.start_state?
        end
        x.state_type = :start
      end
      x
    end


    # Sets the end state.
    def end_state= x
      @end_state = x
      if x 
        @states.each do | s |
          s.state_type = nil if s.end_state?
        end
        x.state_type = :end
      end
      x
    end

    def statemachine
      self
    end

    def superstatemachine
      @superstate && @superstate.statemachine
    end

    def dup_deepen!
      super
      @states = @states.dup
      @transitions = @transitions.dup
      if @state
        @state = @state.dup
        @state.statemachine = self
      end
    end

    # Returns ture if we are at the start state.
    def at_start?
      @state.nil? || @state._proto == @start_state
    end

    # Returns true if we are at the end state.
    def at_end?
=begin
      $stderr.puts "at_end? @state #{@state.inspect} #{@state.object_id}"
      $stderr.puts "at_end? @state._proto #{@state._proto.inspect} #{@state._proto.object_id}"
      $stderr.puts "at_end? @end_state #{@end_state.inspect} #{@end_state.object_id}"
=end
      @state._proto == @end_state
    end

    # Go to the start state.
    def start!
      @state = nil
      goto_state! start_state
    end


    # Returns true if a transition is possible from the current state.
    # Queries the transitions' guards.
    def can_transition? trans, *args
      trans = trans.to_sym unless Symbol === trans

      trans = transitions.select do | t |
        t.from_state === @state &&
        t.can_transition?(self, *args)
      end

      trans.size > 0
    end


    # Returns true if a non-ambigious transition is possible from the current state
    # to the given state.
    # Queries the transitions' guards.
    def can_transition_to? state, *args
      transitions_to(state, *args).size == 1
    end


    # Returns a list of valid transitions from current
    # state to the specified state.
    def transitions_to state, *args
      state = state.to_sym unless Symbol === state

      trans = @state.transitions_from.select do | t |
        t.to_state === state &&
        t.can_transition?(self, *args)
      end

      trans
    end


    # Attempt to transition from current state to another state.
    # This assumes that there is not more than one transition
    # from one state to another.
    def transition_to! state, *args
      trans = transitions_to(state, *args)

      case trans.size
      when 0
        raise UnknownTransitionError, state
      when 1
        transition!(trans.first, *args)
      else
        raise AmbigousTransitionError, state
      end
    end


    # Execute a transition from the current state.
    def transition! name, *args
      if Transition === name
        trans = name

        _log "transition! from #{@state.name.inspect} via #{name.inspect}"
        
        trans = nil unless @state === trans.from_state && trans.can_transition?(self, *args)
      else
        name = name.to_sym unless Symbol === name
        
        # start! unless @state
        
        _log "transition! from #{@state.name.inspect} via #{name.inspect}"
        
        # Find a valid transition.
        trans = @state.transitions_from.select do | t |
          # $stderr.puts "  testing t = #{t.inspect}"
          t === name &&
          t.can_transition?(self, *args)
        end

        _log "transition! from #{@state.name.inspect} via #{name.inspect} found #{trans.inspect}"

        if trans.size > 1
          raise AmbigousTransitionError, "from #{@state.name.inspect} to #{name.inspect}"
        end

        trans = trans.first
      end

      if trans
        execute_transition!(trans, *args)
      else
        raise CannotTransitionError, name
      end
    end


    # Adds a state to this statemachine.
    def add_state! s
      _log "state #{s.inspect}"

      if @states.find { | x | x.name == s.name }
        raise ArgumentError, "state of named #{s.name.inspect} already exists"
      end

      @states << s
      s.statemachine = self

      s
    end


    # Adds a state to this statemachine.
    def add_transition! t
      _log "transition #{t.inspect}"

      if @transitions.find { | x | x.name == t.name }
        raise ArgumentError, "transition named #{s.name.inspect} already exists"
      end

      @transitions << t
      t.statemachine = self
      t.to_state.transition_added!
      t.from_state.transition_added!

      t
    end


    #####################################


    # Returns the Dot name for this statemachine.
    def to_dot_name
      "#{superstate ? superstate.to_dot_name : name}"
    end


    # Returns the Dot label for this statemachine.
    def to_dot_label
      @superstate ? "#{@superstate.statemachine.name}::#{name}" : name.to_s
    end


    # Renders this statemachine as Dot syntax.
    def to_dot f
      type = @superstate ? "subgraph #{to_dot_name}" : "digraph"
      do_graph = true

      f.puts "\n// {#{inspect}"
      f.puts "#{type} {" if do_graph
      f.puts %Q{  label = #{to_dot_label.inspect}}

      f.puts %Q{  #{(to_dot_name + "_START").inspect} [ shape="rectangle", label="#{to_dot_label} START", style=filled, fillcolor=grey, fontcolor=black ]; }

      states.each { | x | x.to_dot f }

      transitions.each { | x | x.to_dot f }

      f.puts "}" if do_graph
      f.puts "// } #{inspect}\n"
    end 
    

    #####################################


    def builder opts = { }, &blk
      b = Builder.new
      if block_given?
        b.statemachine(self, opts, &blk)
        self
      else
        b
      end
    end


    #####################################

    def _log *args
      case 
      when IO === @logger
        @logger.puts "#{self.inspect} : #{state && state.name.inspect} : #{args * " "}"
      when defined?(::Log4r) && (Log4r::Logger === @logger)
        args.unshift :debug if args.size < 0
        @logger.send(*args)
      when (x = superstatemachine)
        x._log *args
      end
    end


    private
    

    # Executes transition.
    def execute_transition! trans, *args
      _log "executing transition #{(trans.name).inspect} #{args.inspect}"

      old_state = @state

      trans.before_transition!(self, *args)

      goto_state!(trans.to_state, *args) do 
        trans.during_transition!(self, *args)

        trans.after_transition!(self, *args)

        @history << [ Time.now.gmtime, old_state, trans, @state ]                   
      end

      self
    end


    # Moves from one state machine to another.
    def goto_state! state, *args
      old_state = @state

      if @state
        _log "leaving state #{(@state && @state.name).inspect}"
        @state.exit_state!(*args)
      end

      yield if block_given?
      
      @state = state.dup
      @state.statemachine = self

      _log "entering state #{state.inspect}"
      @state.enter_state!(*args)

      self
    rescue Exception => err
      @state = old_state
      raise err
    end

  end # class


  # A state in a statemachine.
  # A state may contain another statemachine.
  class State < Base
    # This state's statemachine.
    attr_accessor :statemachine

    # This state type, :start, :end or nil.
    attr_accessor :state_type

    # This state's substatemachine, or nil.
    attr_accessor :substatemachine

    # The context for enter_state!, exit_state!
    attr_accessor :context


    def intialize opts
      @statemachine = nil
      @state_type = nil
      @substatemachine = nil
      super
    end


    def dup_deepen!
      super
      if @substatemachine
        @substatemachine = @substatemachine.dup
        @substatemachine.superstate = self
      end
    end


    # Returns the local context or the statemachine's context.
    def context
      @context || 
        statemachine.context
    end


    # Returns this state's substatemathine's state.
    def substate
      @substatemachine && @substatemachine.state
    end


    # Returns the state's statemachine's superstate, if it exists.
    def superstate
      @statemachine.superstate
    end


    # Is this a start state?
    def start_state?
      @state_type == :start
    end


    # Is this an end state?
    def end_state?
      @state_type == :end
    end


    # Called after a new transition connected to this state.
    def transition_added!
      @transitions =
        @transitions_to =
        @transitions_from = 
        nil
    end


    # Returns a list of transitions to or from this state.
    def transitions
      @transitions ||=
        statemachine.transitions.select { | x | x.to_state === self || x.from_state === self }.freeze
    end


    # Returns a list of transitions to this state.
    def transitions_to
      @transitions_to ||=
        transitions.select { | x | x.to_state === self }.freeze
    end


    # Returns a list of transitions from this state.
    def transitions_from
      @transitions_from ||=
        transitions.select { | x | x.from_state === self }.freeze
    end


    # Returns true if this state matches x.
    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        @name === x.name :
        x === @name
    end
    

    # Clients can override.
    def enter_state! *args
      _notify! :enter_state!, args
      if @substatemachine
        @substatemachine.start! # ???
      end
    end


    # Clients can override.
    def exit_state! *args
      _notify! :exit_state!, args
    end


    # Returns an array representation of this state.
    # may include substates.
    def to_a
      x = [ name ]
      if substate
        x += substate.to_a
      end
      x
    end


    # Returns the string representation of this state.
    def to_s
      if substate
        "[ #{super} #{substate} ]" 
      else
        super
      end
    end

    
    def inspect
      "#<#{self.class} #{name.inspect} #{substate && substate.inspect}>"
    end

    
    def _log *args
      statemachine._log(*args)
    end


    # Returns the Dot name for this state.
    def to_dot_name
      "#{statemachine.to_dot_name}_#{name}" # .inspect
    end
    

    # Returns the Dot syntax for this state.
    def to_dot f
      shape =
      case
        # when @substatemachine
        # :egg
      when end_state?
        :rectangle
      else
        :oval
      end

      f.puts "\n// #{self.inspect}"
      f.puts %Q{#{to_dot_name.inspect} [ shape="#{shape}", label=#{name.to_s.inspect}, style=filled, color=black, #{end_state? ? 'fillcolor=gray, fontcolor=black' : 'fillcolor=white, fontcolor=black'}];}
      if start_state?
        f.puts "#{(statemachine.to_dot_name + '_START').inspect} -> #{to_dot_name.inspect};"
      end
      if @substatemachine
        @substatemachine.to_dot f
        f.puts "#{to_dot_name.inspect} -> #{(@substatemachine.to_dot_name + '_START').inspect} [ style=dashed ];"
      end
    end


    # Delegate other methods to substatemachine, if exists.
    def method_missing sel, *args, &blk
      if @substatemachine && @substatemachine.respond_to?(sel)
        return @substatemachine.send(sel, *args, &blk)
      end
      super
    end

  end # class


  # Represents a transition from one state to another state in a statemachine.
  class Transition < Base
    # The statemachine of this transition.
    attr_accessor :statemachine

    # The origin state.
    attr_accessor :from_state

    # The destination state.
    attr_accessor :to_state

    # The context for can_transition?, before_transition!, during_transition!, after_transition!
    attr_accessor :context


    # Returns the local context or the statemachine.context.
    def context(sm = statemachine)
      @context || 
        sm.context
    end


    def === x
      # $stderr.puts "#{self.inspect} === #{x.inspect}"
      self.class === x ?
        x.name === self.name :
        x === self.name
    end


    # Clients can override.
    def can_transition? sm, *args
      result = _notify! :can_transition?, args, sm
      result.nil? ? true : result
    end

    # Clients can override.
    def before_transition! sm, *args
      _notify! :before_transition!, args, sm
      self
    end

    # Clients can override.
    def during_transition! sm, *args
      _notify! :during_transition!, args, sm
      self
    end

    # Clients can override.
    def after_transition! sm, *args
      _notify! :after_transition!, args, sm
      self
    end

    def inspect
      "#<#{self.class} #{from_state.name} === #{self.name} ==> #{to_state.name}>" 
    end

    def _log *args
      statemachine._log(*args)
    end

    # Renders the Dot syntax for this Transition.
    def to_dot f
      f.puts "\n// #{self.inspect}"
      f.puts "#{from_state.to_dot_name.inspect} -> #{to_state.to_dot_name.inspect} [ label=#{name.to_s.inspect}, color=black ];"
    end

  end # class


  # DSL for building state machines.
  class Builder
    # Returns the top-level statemachine.
    attr_accessor :result

    def initialize &blk
      @context = { }
      @context_stack = { }
      build &blk if block_given?
    end

    def build &blk
      instance_eval &blk
      result
    end


    ##################################################################
    # DSL methods
    #

    # Creates a new statemachine or augments an existing one.
    #
    # Create syntax:
    #
    #   sm = builder.build do 
    #     statemachine :my_statemachine do
    #       start_state :a
    #       end_state   :end
    #       state :a
    #       state :b
    #       state :end
    #       transition :a, :b
    #       transition :b, :end
    #     end
    #   end
    #
    # Augmenting syntax:
    #
    #   sm.builder do 
    #     state :c
    #     transition :a, :c
    #     transition :c, :end
    #   end
    #
    def statemachine name = nil, opts = { }, &blk
      # Create a sub state machine?
      s = @context[:state]
      if s
        name = s.name
      end
      raise(ArgumentError, 'invalid name') unless name

      case name
      when Statemachine
        sm = name
        name = sm.name
      else
        name = name.to_sym unless Symbol === name
        
        opts[:name] = name
        sm = Statemachine.new opts
      end

      @result ||= sm

      # Attach state to substate machine.
      if s
        s.substatemachine = sm 
        sm.superstate = s
      end

      _with_context(:state, nil) do
        _with_context(:start_state, nil) do 
          _with_context(:end_state, nil) do
            _with_context(:statemachine, sm) do 
              if blk
                instance_eval &blk 
                
                sm.start_state = _find_state(@context[:start_state]) if @context[:start_state]
                sm.end_state   = _find_state(@context[:end_state])   if @context[:end_state]
              end
            end
          end
        end
      end
    end


    # Defines the start state.
    def start_state state
      @context[:start_state] = state
    end


    # Defines the end state.
    def end_state state
      @context[:end_state] = state
    end


    # Creates a state.
    def state name, opts = { }, &blk
      opts[:name] = name
      s = _find_state opts
      _with_context :state, s do 
        instance_eval &blk if blk
      end
    end


    # Creates a transition between two states.
    #
    # Syntax:
    #
    #   state :a do 
    #     transition :b
    #   end
    #   state :b
    #
    # Creates a transition named :'a->b' from state :a to state :b.
    #
    #   state :a
    #   state :b
    #   transition :a, :b
    #
    # Creates a transition name :'a->b' from state :a to state :b.
    #
    #   state :a do
    #     transition :b, :name => :a_to_b
    #   end
    #   state b:
    #
    # Creates a transition named :a_to_b from state :a to state :b.
    def transition *args, &blk
      if Hash === args.last
        opts = args.pop
      else
        opts = { }
      end

      case args.size
      when 1 # to_state
        opts[:from_state] = @context[:state]
        opts[:to_state] = args.first
      when 2 # from_state, to_state
        opts[:from_state], opts[:to_state] = *args
      else
        raise(ArgumentError)
      end

      raise ArgumentError unless opts[:from_state]
      raise ArgumentError unless opts[:to_state]
      
      opts[:from_state] = _find_state opts[:from_state]
      opts[:to_state]   = _find_state opts[:to_state]

      t = _find_transition opts
      _with_context :transition, t do
        instance_eval &blk if blk
      end
    end


    # Dispatches method to the current context.
    def method_missing sel, *args, &blk
      if @current
        return @current.send(sel, *args, &blk)
      end
      super
    end


    private

    def _with_context name, val
      current_save = @current
 
      (@context_stack[name] ||= [ ]).push(@context[name])
      
      @current = 
        @context[name] = 
        val
      
      yield
      
    ensure
      @current = current_save
      
      @context[name] = @context_stack[name].pop
    end
   

    # Locates a state by name or creates a new object.
    def _find_state opts, create = true
      $stderr.puts "_find_state #{opts.inspect}, #{create.inspect} from #{caller(1).first}" if ! create

      raise ArgumentError, "opts" unless opts

      name = nil
      case opts
      when String, Symbol
        name = opts.to_sym
        opts = { }
      when Hash
        name = opts[:name].to_sym
      when State
        return opts
      else
        raise ArgumentError, "given #{opts.inspect}"
      end

      raise ArgumentError, "name" unless name

      s = @context[:statemachine].states.find do | x | 
        name === x.name
      end

      if create && ! s
        opts[:name] = name
        opts[:statemachine] = @context[:statemachine]
        s = State.new opts
        @context[:statemachine].add_state! s
      end
      
      s
    end

    # Locates a transition by name or creates a new object.
    def _find_transition opts
      raise ArgumentError, "opts" unless Hash === opts

      opts[:from_state] = _find_state opts[:from_state]
      opts[:to_state] = _find_state opts[:to_state]
      opts[:name] ||= "#{opts[:from_state].name}->#{opts[:to_state].name}".to_sym

      t = @context[:statemachine].transitions.find do | x |
        opts[:name] == x.name
      end
      
      unless t
        opts[:statemachine] = @context[:statemachine]
        t = Transition.new opts
        @context[:statemachine].add_transition! t
      end
      
      t
    end
    
  end # class

end # module


###############################################################################
# EOF