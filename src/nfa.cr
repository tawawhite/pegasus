module Pegasus
  module Nfa
    class Transition
      property other : State

      def initialize(@other)
      end
    end

    class CharTransition < Transition
      getter char : Char

      def initialize(@char, @other)
      end
    end

    class LambdaTransition < Transition
      def initialize(@other)
      end
    end

    class AnyTransition < Transition
      def initialize(@other)
      end
    end

    class State
      property final : Bool
      property id : Int64
      property transitions : Array(Transition)
      
      def initialize(*, @id : Int64 = -1, @final : Bool = false, @transitions = [] of Transition)
      end
    end

    class StateChain
      property start : State
      property final : State

      def initialize(@start, @final = @start)
      end

      def append!(other : StateChain)
        if @final == nil
          @start = other.start
          @final = other.final
        elsif other.start
          @final.not_nil!.transitions << LambdaTransition.new(other.start.not_nil!)
          @final = other.final
        end
        return self
      end
      
      def append!(other : Nil)
        return self
      end
    end

    class Nfa
      getter states : Set(State)
      property start : State?

      def initialize(str)
        @last_id = 0_i64
        @states = Set(State).new
        @start = from_regex(str)
      end

      def state(*, final : Bool)
        new_state = State.new(id: @last_id, final: final);
        @last_id += 1
        @states << new_state
        return new_state
      end

      private def nfa_plus(chain)
        if chain.start && chain.final
          new_final = state(final: false)
          new_start = state(final: false)
          new_final.transitions << LambdaTransition.new(new_start)
          chain.final.transitions << LambdaTransition.new(new_final)
          new_start.transitions << LambdaTransition.new(chain.start)

          chain.start = new_start
          chain.final = new_final
        end
      end

      private def nfa_star(chain)
        if chain.start && chain.final
          new_final = state(final: false)
          new_start = state(final: false)
          new_final.transitions << LambdaTransition.new(new_start)
          new_start.transitions << LambdaTransition.new(new_final)
          chain.final.transitions << LambdaTransition.new(new_final)
          new_start.transitions << LambdaTransition.new(chain.start)

          chain.start = new_start
          chain.final = new_final
        end
      end

      private def nfa_question(chain)
        if chain.start && chain.final
          new_final = state(final: false)
          new_start = state(final: false)
          new_start.transitions << LambdaTransition.new(new_final)
          chain.final.transitions << LambdaTransition.new(new_final)
          new_start.transitions << LambdaTransition.new(chain.start)

          chain.start = new_start
          chain.final = new_final
        end
      end

      private def from_regex_expr(tokens, *, require_parenths = true)
        substring_stack = [] of StateChain
        current_chain = nil
        sub_chain = nil

        modifiers = {
          '+' => ->nfa_plus(StateChain),
          '*' => ->nfa_star(StateChain),
          '?' => ->nfa_question(StateChain)
        }

        while tokens.first? && tokens.first != ')'
          char = tokens.delete_at(0)

          if modifier = modifiers[char]?
            raise "Invalid operator" unless sub_chain
            modifier.call(sub_chain)
            next
          end

          current_chain = current_chain.try(&.append!(sub_chain)) || sub_chain
          if char == '('
            sub_chain = from_regex_expr(tokens)
          elsif char == '.'
            empty_state = state(final: false)
            actual_state = state(final: false)

            empty_state.transitions << AnyTransition.new(actual_state)
            sub_chain = StateChain.new(empty_state, actual_state)
          elsif char == '|'
            substring_stack.push current_chain if current_chain
            current_chain = nil
            sub_chain = nil
          else
            if char == '\\'
              raise "Invalid escape code" unless tokens.first?
              char = tokens.delete_at(0)
            end

            empty_state = state(final: false)
            actual_state = state(final: false)
            empty_state.transitions << CharTransition.new(char.not_nil!, actual_state)
            sub_chain = StateChain.new(empty_state, actual_state)
          end
        end
        current_chain = current_chain.try(&.append!(sub_chain)) || sub_chain

        if require_parenths && tokens.first? == ')'
          tokens.delete_at(0)
        elsif (require_parenths ^ (tokens.first? == ')'))
          raise "Mismatched parentheses"
        end

        if substring_stack.size > 0
          substring_stack.push current_chain if current_chain
          start_state = state(final: false)
          end_state = state(final: false)
          substring_stack.compact!.each do |chain|
            start_state.transitions << LambdaTransition.new(chain.start)
            chain.final.transitions << LambdaTransition.new(end_state)
          end
          current_chain = StateChain.new(start_state, end_state)
        end

        return current_chain
      end

      private def from_regex(str)
        tokens = str.chars
        chain = from_regex_expr(tokens, require_parenths: false)
        final_state = state(final: true)
        final_chain = StateChain.new(final_state, final_state)
        return (chain.try(&.append!(final_chain)) || final_chain).start
      end
    end
  end
end