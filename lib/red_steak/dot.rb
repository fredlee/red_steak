
module RedSteak

  # Renders a StateMachine as a Dot syntax stream.
  class Dot < Base
    # The root statemachine to be rendered.
    attr_accessor :stateMachine
    alias :statemachine  :stateMachine  # not UML
    alias :statemachine= :stateMachine= # not UML

    # The output stream.
    attr_accessor :stream

    # The output Dot file.
    attr_accessor :file_dot

    # The output SVG file.
    attr_accessor :file_svg

    
    def initialize opts = { }
      @dot_name = { }
      @dot_label = { }
      @dot_id = 0
      super
    end


    def dot_name x
      @dot_name[x] ||= 
        "x#{@dot_id += 1}"
    end


    # Returns the Dot label for the object.
    def dot_label x
      @dot_label[x] ||=
        _dot_label x
    end


    def _dot_label x
      # $stderr.puts "  _dot_label #{x.inspect}"
      case x
      when StateMachine, State
        x.to_s

      when Transition
        label = x.name.to_s
        
        # See UML Spec 2.1 superstructure p. 574
        # Put the Transition#guard and #effect in the label.
        [ 
         [ :show_guards,  :guard,  '[%s]' ],
         [ :show_effects, :effect, '/%s' ],
        ].each do | (opt, sel, fmt) |
         
          if options[opt]
            case b = x.send(sel)
            when nil
              # NOTHING
            when String, Symbol
              b = b.inspect
            else
              b = '...'
            end
            if b
              label = label + " \n" + (fmt % b)
            end
          end
        end
        
        # $stderr.puts "  _dot_label #{x.inspect} => #{label.inspect}"
        
        label

      when String, Integer
        x.to_s

      else
        raise ArgumentError, x.inspect
      end
    end


    # Renders object as Dot syntax.
    def render x = @stateMachine
      case x
      when Machine
        options[:history] ||= x.history
        render x.stateMachine
      when StateMachine
        render_root x
      when State
        render_State x
      when Transition
        render_Transition x
      else
        raise ArgumentError, x.inspect
      end
    end


    def render_root sm
      @stateMachine ||= sm
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
          stream.puts "#{(dot_name(s.stateMachine) + '_START')} -> #{dot_name(s)};"
        end
        if ssm = s.submachine
          render_transitions(ssm)
        end
      end
    end


    # Renders the StateMachine as Dot syntax.
    def render_StateMachine sm, dot_opts = { }
      stream.puts "\n// {#{sm.inspect}"
      type = "subgraph cluster_#{dot_name(sm)}"

      dot_opts[:label] ||= dot_label(sm.superstate)
      dot_opts[:shape] = :box
      dot_opts[:style] = 'filled,rounded'
      dot_opts[:fillcolor] ||= :white
      dot_opts[:fontcolor] ||= :black

      stream.puts "#{type} {"

      stream.puts %Q{  label=#{dot_opts[:label].inspect}; }
      stream.puts %Q{  shape="#{dot_opts[:shape]}"; }
      stream.puts %Q{  style="#{dot_opts[:style]}"; }
      stream.puts %Q{  fillcolor=#{dot_opts[:fillcolor]}; }
      stream.puts %Q{  fontcolor=#{dot_opts[:fontcolor]}; }

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
        :label => dot_label(s),
        :shape => :box,
        :style => :filled,
      }

      case
      when s.end_state?
        dot_opts[:label] = ""
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
              sequence << i - 1
            when s1
              sequence << i
            end
          end
        end

        unless sequence.empty?
          sequence.uniq!
          sequence.sort!
          if options[:show_history_sequence] 
            dot_opts[:label] += ": (#{sequence * ', '})"
          end
          dot_opts[:fillcolor] = :grey
          dot_opts[:fontcolor] = :black
        end
      end


      if ssm = s.submachine
        render_StateMachine(ssm, dot_opts)
        # stream.puts %Q{#{dot_name(s)} -> #{(dot_name(ssm) + '_START')} [ label="substate", style=dashed ];}
      else
        stream.puts %Q{  node [ shape="#{dot_opts[:shape]}", label=#{dot_opts[:label].inspect}, style="#{dot_opts[:style]},rounded", color=#{dot_opts[:color]}, fillcolor=#{dot_opts[:fillcolor]}, fontcolor=#{dot_opts[:fontcolor]} ] #{dot_name(s)};}
      end
    end


    # Renders the Dot syntax for the Transition.
    def render_Transition t
      stream.puts "\n// #{t.inspect}"

      # $stderr.puts "  #{t.inspect}\n    #{options.inspect}"

      dot_opts = { 
        :label => dot_label(t),
        :color => options[:show_history] ? :gray : :black,
        :fontcolor => options[:show_history] ? :gray : :black,
      }

      source_name = "#{dot_name(t.source)}"
      if ssm = t.source.submachine
        source_name = "#{dot_name(ssm)}_START"
      end

      target_name = "#{dot_name(t.target)}"
      if ssm = t.target.submachine
        target_name = "#{dot_name(ssm)}_START"
      end

      if options[:show_history] && options[:history]
        sequence = [ ]

        # $stderr.puts "\n  trans = #{t.inspect}, sm = #{t.stateMachine.inspect}"
        options[:history].each_with_index do | hist, i |
          if hist[:transition] === t
            # $stderr.puts "  #{i} hist = #{hist.inspect}"
            sequence << i
          end
        end

        unless sequence.empty?
          sequence.sort!
          sequence.uniq!

          dot_opts[:color] = :black
          dot_opts[:fontcolor] = :black
          dot_opts[:label] = "(#{sequence * ','}) #{dot_opts[:label]}"
        end
      end

      stream.puts "#{source_name} -> #{target_name} [ label=#{dot_opts[:label].inspect}, color=#{dot_opts[:color]}, fontcolor=#{dot_opts[:fontcolor]} ];"

      self
    end


    def render_opts x
      case x
      when Hash
        x.keys.map do | k |
          # HUH?
        end.join(', ')
      when Array
      else
        x.to_s.inspect
      end
    end


    # machine can be a Machine or a Statemachine object.
    #
    # Returns self.
    #
    # Options: 
    #   :dir  
    #     The directory to create the .dot and .dot.svg files.
    #     Defaults to '.'
    #   :name 
    #     The base filename to use.  Defaults to the name of
    #     StateMachine object.
    #   :show_history
    #     If true, the history stored in Machine is shown as
    #     numbered transitions between states.
    #
    # Results:
    #
    #   file_dot
    #     The *.dot file.
    #
    #   file_svg
    #     The *.svg file.
    #     Defaults to "#{file_dot}.svg"
    #
    def render_graph(machine, opts={})
      case machine
      when RedSteak::Machine
        sm = machine.statemachine
      when RedSteak::StateMachine
        sm = machine
      end

      # Compute dot file name.
      unless file_dot
        dir = opts[:dir] || '.'
        file = "#{dir}/"
        file += opts[:name_prefix].to_s
        opts[:name] ||= sm.name
        file += opts[:name].to_s 
        file += opts[:name_suffix].to_s
        file += '-history' if opts[:show_history]
        file += ".dot"
        self.file_dot = file
      end

      # Write the dot file.
      File.open(file_dot, 'w') do | fh |
        opts[:stream] = fh
        RedSteak::Dot.new(opts).render(machine)
      end
      opts[:stream] = nil

      # Compute the SVG file name.
      self.file_svg ||= "#{file_dot}.svg"

      # Render dot to SVG.
      cmd = "dot -V"
      if system("#{cmd} >/dev/null 2>&1") == true
        File.unlink(file_svg) rescue nil
        cmd = "dot -Tsvg:cairo:cairo #{file_dot.inspect} -o #{file_svg.inspect}"
        $stderr.puts cmd
        result = `#{cmd} 2>&1`
        if result =~ /Warning: language .* not recognized, use one of:/
          cmd = "dot -Tsvg #{file_dot.inspect} -o #{file_svg.inspect}"
          $stderr.puts cmd
          result = `#{cmd} 2>&1`
        end
        $stdout.puts "View file://#{file_svg}"
      else
        $stderr.puts "Warning: #{cmd} failed"
      end

      self
    end


    # Returns SVG data of the graph, using a temporary file.
    def render_graph_svg_data machine, opts = { }
      require 'tempfile'
      tmp = Tempfile.new("red_steak_dot")
      self.file_dot = tmp.path + ".dot"
      self.file_svg = nil
      render_graph(machine, opts)
      result = File.open(self.file_svg, "r") { | fh | fh.read }
      if opts[:xml_header] == false || options[:xml_header] == false
        result.sub!(/\A.*?<svg /m, '<svg ')
      end
      # puts "#{result[0..200]}..."
      result
    ensure
      tmp.unlink rescue nil
      File.unlink(self.file_dot) rescue nil
      File.unlink(self.file_svg) rescue nil
    end

  end # class

end # module


###############################################################################
# EOF

