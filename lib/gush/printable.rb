module Gush
  module Printable
    def print_tree(level = 0)
      if is_root?
        print "*"
      else
        print "|" unless parent.is_last_sibling?
        print(' ' * (level - 1) * 4)
        print(is_last_sibling? ? "+" : "|")
        print "---"
        print(has_children? ? "+" : ">")
      end

      colored_name = " #{name}"
      if running?
        colored_name = colored_name.yellow
      elsif failed?
        colored_name = colored_name.red
      elsif finished?
        colored_name = colored_name.green
      end

      puts colored_name

      children { |child| child.print_tree(level + 1) if child } # Child might be 'nil'
    end
  end
end
