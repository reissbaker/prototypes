require 'pty'
require 'io/console'

args = ARGV.clone

class BlockPty
  attr_reader :controller, :device

  def initialize(controller, device, &block)
    @controller = controller
    @device = device
    @block = block
  end

  def call
    err = nil
    out = nil

    orig_stdout = $stdout.clone
    orig_stderr = $stderr.clone
    orig_stdin = $stdin.clone
    $stdout.reopen(device)
    $stderr.reopen(device)
    $stdin.reopen(device)

    begin
      out = @block.call(self)
    # With the pipes all fucked up, apparently Ruby won't actually exit on exceptions!
    # Rescue _everything_ here, and we'll re-raise correctly in the ensure block once the pipes are
    # back.
    rescue Exception => e
      err = e
    end
  ensure
    $stdout.reopen(orig_stdout)
    $stderr.reopen(orig_stderr)
    $stdin.reopen(orig_stdin)

    raise err unless err.nil?
    return out
  end

  def close_device
    device.close
  end

  def close_controller
    controller.close
  end

  class << self
    def in_pty(&block)
      controller, device = PTY.open
      self.new(controller, device, &block)
    end

    def get_lines(pty)
      lines = []
      begin
        loop do
          ready, _, _ = IO.select([pty.controller])
          output = ready.first.read_nonblock(1024)
          saw_return = false
          output.each_char do |ascii_char|
            char = ascii_char.force_encoding('utf-8')

            curr_line = lines[lines.length - 1]
            if curr_line.nil?
              curr_line = ''
              lines << curr_line
            end

            if char == "\n"
              lines << ""
            elsif char != "\r"
              if saw_return
                lines << ''
              end
              lines[lines.length - 1] = curr_line + char
            end

            if char == "\r"
              saw_return = true
            else
              saw_return = false
            end
          end
        end
      rescue Errno::EIO => e
        # This breaks the loop
        # It's thrown when the controller reaches end of input
        # God knows why EOF doesn't work
      end

      lines
    end
  end
end

def enqueue_stdin(pty_block, str)
  # turn off echo before writing to pipe, or else you'll get the str in the log. grab the current
  # stty settings and reuse them, in case the tty already had echo turned off.
  # apparently there's no read accessor on $stdin.echo, so this works around that
  current_stty = `stty -g`
  system("stty -echo")
  pty_block.controller.puts(str)
  system("stty #{current_stty}")
end

pty_block = BlockPty.in_pty do |pty_block|
  puts "hi"
  system("echo 'echoed'")
  system("cat #{__FILE__}")

  enqueue_stdin(pty_block, "yo")

  input = $stdin.gets.chomp
  puts "\nfound input: #{input}"
end

pty_block.()
pty_block.close_device
lines = BlockPty.get_lines(pty_block)
pty_block.close_controller

# Got all the PTY data! Everything from here on down is UI rendering code
_, console_width = IO.console.winsize
HORIZ_MARGIN = 1
VERT_MARGIN = 1
MAX_WIDTH = 80
MIN_WIDTH = console_width - (HORIZ_MARGIN * 2)
WIDTH = [ MAX_WIDTH, MIN_WIDTH ].min
HEIGHT = args.first.to_i
CORNER_BORDER_CHAR = "•"
TL_CHAR = "\u250C"
TR_CHAR = "\u2510"
BL_CHAR = "\u2514"
BR_CHAR = "\u2518"
VERT_BORDER_CHAR = "\u2500"
HORIZ_BORDER_CHAR = "\u2502"
BORDER_HORIZ_PADDING = 1

INNER_LINE_WIDTH = WIDTH - (HORIZ_BORDER_CHAR.length * 2) - (HORIZ_MARGIN * 2) - (BORDER_HORIZ_PADDING * 2) + 1

TITLE = "PTY SCREEN #{INNER_LINE_WIDTH}x#{HEIGHT}"

LEFT_BORDER = (" " * HORIZ_MARGIN) + HORIZ_BORDER_CHAR + (" " * BORDER_HORIZ_PADDING)
RIGHT_BORDER = (" " * BORDER_HORIZ_PADDING) + HORIZ_BORDER_CHAR
FRAME_BOTTOM = (" " * HORIZ_MARGIN) + BL_CHAR + (VERT_BORDER_CHAR * (WIDTH - 2)) + BR_CHAR
FRAME_TOP_LEFT = TL_CHAR + (VERT_BORDER_CHAR * (((WIDTH - TITLE.length - 2) / 2) - 2))
FRAME_TOP_RIGHT = (VERT_BORDER_CHAR * ((WIDTH - FRAME_TOP_LEFT.length - TITLE.length - 2) - 3)) + TR_CHAR

COLORIZED_TITLE = "\e[93m#{TITLE}\e[0m"

def vert_margin
  (0...VERT_MARGIN).each { print "\n" }
end

vert_margin
puts "#{" " * HORIZ_MARGIN}#{FRAME_TOP_LEFT}\u2524 #{COLORIZED_TITLE} \u251c#{FRAME_TOP_RIGHT}"

buffer = []

def stage(buffer, text)
  buffer << LEFT_BORDER + text.ljust(INNER_LINE_WIDTH + 1) + RIGHT_BORDER
end

lines.each do |output|
  remaining = output.length

  if remaining == 0
    stage(buffer, "")
    next
  end

  index = 0

  while remaining > 0
    line = [remaining, INNER_LINE_WIDTH].min
    stage(buffer, output[index...(index + line)])
    remaining -= line
    index += line
  end
end

start_offset = [ 0, buffer.length - HEIGHT].max
screen = buffer[start_offset..-1]
if screen.length < HEIGHT
  (screen.length...HEIGHT).each do
    stage(screen, "")
  end
end
puts screen.join("\n")
puts FRAME_BOTTOM
vert_margin
