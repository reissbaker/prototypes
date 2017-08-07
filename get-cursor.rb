require 'io/console'

# to track and skip input, all you need to do is watch for newlines on stdin
# grab the cursor pos after your last render, and then update just the y-position from newlines on
# stdin as you see them come in
# before doing anything, jump to last pos (offset by newline count)
# make sure all input happens thru yr cursor tracking class
#
# crazy TUI idea: floating window on the bottom. logs flow down normally with full scrollback;
# floating window gets continually erased before new logs are printed, then redrawn after.
class Cursor
  class << self
    def pos
      res = ''

      $stdin.raw do |stdin|
        $stdout << "\e[6n"
        $stdout.flush
        while (c = stdin.getc) != 'R'
          res << c if c
        end
      end

      m = res.match /(?<row>\d+);(?<column>\d+)/

      { row: Integer(m[:row]), column: Integer(m[:column]) }
    end
  end
end

puts Cursor.pos  #=> {:row=>25, :column=>1}
