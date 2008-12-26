
module RedSteak

  # Renders a Statemachine as a Dot syntax stream.
  class Dot < Base
    # The root statemachine to be rendered.
    attr_accessor :statemachine

    # The output stream.
    attr_accessor :stream


    def initialize opts = { }
      @dot_name = { }
      @dot_id = 0
      super
    end


    # Returns the Dot name for the object.
    def dot_name x
      case 
      when Statemachine
        x.superstate ? "#{dot_name(x.superstate)}::#{x.name}" : x.name.to_s
      when State
        "#{dot_name(x.statemachine)}::#{x.name}" # x.inspect
#      when Transition
      else
        raise ArgumentError, x
      end
    end


    def dot_name x
      (@dot_name ||= { })[x] ||= "x#{@dot_id += 1}"
    end


    # Returns the Dot label for the object.
    def dot_label x
      case
      when Statemachine
        x.superstate ? "#{dot_label(x.superstatemachine)}::#{x.name}" : x.name.to_s
#      when State
#      when Transition
      else
        raise ArgumentError, x
      end
    end


    # Renders object as Dot syntax.
    def render x = @statemachine
      case x
      when Machine
        options[:history] ||= x.history
        render x.statemachine
      when Statemachine
        render_root x
      when State
        render_State x
      when Transition
        render_Transition x
      else
        raise ArgumentError, x
      end
    end


    def render_root sm
      @statemachine ||= sm
      stream.puts "\n// {#{sm.inspect}"
      stream.puts "digraph #{dot_name(sm)} {"

=begin
      stream.puts %Q{  node [fontname="Verdana"]; }
      stream.puts %Q{  fontname="Verdana"; }
=end
      stream.puts %Q{  label=#{dot_label(sm).inspect}; }
 
      # stream.puts "subgraph ROOT {"

      stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{(dot_name(sm) + "_START")}; }

      sm.states.each { | s | render_State(s) }
      
      render_transitions(sm)

      stream.puts "}"
      # stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end


    def render_transitions sm
      sm.transitions.each { | t | render(t) }
      sm.states.each do | s |
        if s.start_state?
          stream.puts "#{(dot_name(s.statemachine) + '_START')} -> #{dot_name(s)};"
        end
        if ssm = s.substatemachine
          render_transitions(ssm)
        end
      end
    end


    # Renders the Statemachine as Dot syntax.
    def render_Statemachine sm
      stream.puts "\n// {#{sm.inspect}"
      # type = sm.superstate ? "subgraph #{dot_name(sm)}" : :digraph
      type = "subgraph cluster_#{dot_name(sm)}"

      stream.puts "#{type} {"
      if type != :digraph
        stream.puts %Q{  label=#{dot_label(sm.superstate).inspect}; }
        stream.puts %Q{  shape="box"; }
        stream.puts %Q{  style="filled,rounded"; }
        stream.puts %Q{  fillcolor="white"; }
        stream.puts %Q{  fontcolor="black"; }
      end

      stream.puts %Q{  node [ shape="circle", label="", style=filled, fillcolor=black ] #{(dot_name(sm) + "_START")}; }

      sm.states.each { | s | render(s) }

      stream.puts "}"
      stream.puts "// } #{sm.inspect}\n"
    end 
    

    # Renders the State object as Dot syntax.
    def render_State s
      stream.puts "\n// #{s.inspect}"

      dot_opts = {
        :color => :black,
        :label => s.name.to_s,
        :shape => :box,
        :style => :filled,
      }

      case
        # when @substatemachine
        # :egg
      when s.end_state?
        dot_opts[:shape] = :doublecircle
        dot_opts[:fillcolor] = :black
        dot_opts[:fontcolor] = :white
      else
        dot_opts[:fillcolor] = :white
        dot_opts[:fontcolor] = :black
      end

      if options[:show_history] && options[:history]
        sequence = [ ]

        options[:history].each_with_index do | hist, i |
          if (s0 = hist[:previous_state] === s) || 
             (s1 = hist[:new_state] === s)
            # $stderr.puts "hist = #{hist.inspect} i = #{i.inspect}"
            case
            when s0
              sequence << i
            when s1
              sequence << i + 1
            end
          end
        end

        sequence.uniq!
        sequence.sort!
        unless sequence.empty?
          if options[:show_history_sequence] 
            dot_opts[:label] += ": (#{sequence * ', '})"
          end
          dot_opts[:fillcolor] = :grey
          dot_opts[:fontcolor] = :black
        end
      end


      if ssm = s.substatemachine
        render_Statemachine(ssm)
        # stream.puts %Q{#{dot_name(s)} -> #{(dot_name(ssm) + '_START')} [ label="substate", style=dashed ];}
      else
        stream.puts %Q{  node [ shape="#{dot_opts[:shape]}", label=#{dot_opts[:label].inspect}, style="#{dot_opts[:style]},rounded", color=#{dot_opts[:color]}, fillcolor=#{dot_opts[:fillcolor]}, fontcolor=#{dot_opts[:fontcolor]} ] #{dot_name(s)};}
      end
    end


    # Renders the Dot syntax for the Transition.
    def render_Transition t
      stream.puts "\n// #{t.inspect}"

      dot_opts = { 
        :label => t.name.to_s,
        :color => options[:show_history] ? :gray : :black,
        :fontcolor => options[:show_history] ? :gray : :black,
      }

      source_name = "#{dot_name(t.source)}"
      if ssm = t.source.substatemachine
        source_name = "#{dot_name(ssm)}_START"
      end

      target_name   = "#{dot_name(t.target)}"
      if ssm = t.target.substatemachine
        target_name = "#{dot_name(ssm)}_START"
      end


      sequence = [ ]

      if options[:show_history] && options[:history]
        # $stderr.puts "\n  trans = #{t.inspect}, sm = #{t.statemachine.inspect}"
        options[:history].each_with_index do | hist, i |
          if hist[:transition] === t
            # $stderr.puts "  #{i} hist = #{hist.inspect}"
            sequence << (i + 1)
          end
        end

        sequence.sort!
        sequence.uniq!
      end

      unless sequence.empty?
        dot_opts[:color] = :black
        dot_opts[:fontcolor] = :black
        sequence.each do | seq |
          stream.puts "#{source_name} -> #{target_name} [ label=#{('(' + seq.to_s + ') ' + t.name.to_s).inspect}, color=#{dot_opts[:color]}, fontcolor=#{dot_opts[:fontcolor]} ];"
        end
      else 
        stream.puts "#{source_name} -> #{target_name} [ label=#{dot_opts[:label].inspect}, color=#{dot_opts[:color]}, fontcolor=#{dot_opts[:fontcolor]} ];"

      end
      
    end


    def render_opts x
      case x
      when Hash
        x.keys.map do | k |
        end.join(', ')
      when Array
      else
        x.to_s.inspect
      end
    end



  end # class

end # module


###############################################################################
# EOF