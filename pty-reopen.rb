require 'pty'
require 'io/console'

args = ARGV.clone

_, console_width = IO.console.winsize
HORIZ_MARGIN = 1
VERT_MARGIN = 1
MAX_WIDTH = 120
MIN_WIDTH = console_width - (HORIZ_MARGIN * 2)
WIDTH = [ MAX_WIDTH, MIN_WIDTH ].min
CORNER_BORDER_CHAR = "•"
TL_CHAR = "\u250C"
TR_CHAR = "\u2510"
BL_CHAR = "\u2514"
BR_CHAR = "\u2518"
VERT_BORDER_CHAR = "\u2500"
HORIZ_BORDER_CHAR = "\u2502"
BORDER_HORIZ_PADDING = 1

INNER_LINE_WIDTH = WIDTH - (HORIZ_BORDER_CHAR.length * 2) - (HORIZ_MARGIN * 2) - (BORDER_HORIZ_PADDING * 2) + 1

class BlockPty
  attr_reader :controller, :terminal

  def initialize
    controller, terminal = PTY.open
    @controller = controller
    @terminal = terminal
    @orig_stdout = nil
    @pid = nil
  end

  def real_puts(str)
    if @orig_stdout.nil?
      $stdout.puts(str)
    else
      @orig_stdout.puts(str)
    end
  end

  def run(&block)
    @pid = Process.fork do
      err = nil

      begin
        @orig_stdout = $stdout.clone
        orig_stderr = $stderr.clone
        orig_stdin = $stdin.clone
        $stdout.reopen(terminal)
        $stderr.reopen(terminal)
        $stdin.reopen(terminal)

        out = block.call(self)
      # With the pipes all fucked up, apparently Ruby won't actually exit on exceptions!
      # Rescue _everything_ here, and we'll re-raise correctly in the ensure block once the pipes are
      # back.
      rescue Exception => e
        err = e
      ensure
        $stdout.reopen(@orig_stdout)
        $stderr.reopen(orig_stderr)
        $stdin.reopen(orig_stdin)
        @orig_stdout = nil
        controller.close
        terminal.close

        raise err unless err.nil?
      end
    end

    terminal.close
    @pid
  end

  def close
    controller.close
    unless @pid.nil?
      _, status = Process.wait2(@pid)
      raise "PTY process exited with status #{status.to_i}" unless status.success?
    end
  end

  class << self
    def get_lines(pty)
      lines = with_buffer do |lines|
        begin
          loop do
            _, _, _ = IO.select([ pty.controller ])
            output = pty.controller.read_nonblock(1024)
            buffer_output(lines, output)
          end
        end
      end

      # Pop off the final line if it's a newline-terminated file
      lines.pop if lines[-1] == ""

      lines
    end

    private

    def with_buffer
      lines = []
      @saw_return = false
      yield lines
    ensure
      @saw_return = false
      return lines
    end

    def buffer_output(lines, output)
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
          if @saw_return
            lines << ''
          end
          lines[lines.length - 1] = curr_line + char
        end

        if char == "\r"
          @saw_return = true
        else
          @saw_return = false
        end
      end
    end
  end
end

def enqueue_stdin(pty_block, str)
  # turn off echo before writing to pipe, or else you'll get the str in the log. grab the current
  # stty settings and reuse them, in case the tty already had echo turned off.
  # apparently $stdin.echo? blocks on macOS, so this is a workaround around that
  current_stty = `stty -g`
  system("stty -echo")
  pty_block.controller.puts(str)
  system("stty #{current_stty}")
end

def print_command(cmd)
  puts "> #{cmd}"
end

def run_command(cmd)
  print_command(cmd)
  system(cmd)
end

pty_block = BlockPty.new

pty_block.run do
  puts "hi\n\n"
  run_command("echo 'echoed'")
  cmd = "cat #{__FILE__}"

  puts "\nlet's run some shit in an inner pty and do some crazy formatting. we will run:"
  print_command(cmd)
  puts "running..."

  # nested!!!
  inner_pty = BlockPty.new
  inner_pty.run do
    system(cmd)
  end

  puts "ran successfully. printing...\n\n"
  lines = BlockPty.get_lines(inner_pty)
  inner_pty.close

  line_number_justification = Math.log10(lines.length).ceil
  screen = []
  indent = "    "
  max_line_length = INNER_LINE_WIDTH - line_number_justification - indent.length - 2

  lines.each_with_index do |line, index|
    start_index = 0
    remaining = line.length
    chunk = [ remaining, max_line_length ].min
    output = line[start_index...chunk]
    start_index += chunk
    screen << "#{indent}#{(index + 1).to_s.rjust(line_number_justification)}: #{output}"
    remaining -= chunk
    while remaining > 0
      chunk = [ remaining, max_line_length ].min
      output = line[start_index...(start_index + chunk)]
      start_index += chunk
      screen << "#{indent}#{' '.rjust(line_number_justification)}  #{output}"
      remaining -= chunk
    end
  end

  puts screen.join("\n")

  puts "\nlet's write some fake input to the controller and read it back from $stdin"

  enqueue_stdin(pty_block, "yo")

  input = $stdin.gets.chomp
  puts "found input: #{input}"
end

lines = BlockPty.get_lines(pty_block)
pty_block.close

# Got all the PTY data! Everything from here on down is UI rendering code
LEFT_BORDER = (" " * HORIZ_MARGIN) + HORIZ_BORDER_CHAR + (" " * BORDER_HORIZ_PADDING)
RIGHT_BORDER = (" " * BORDER_HORIZ_PADDING) + HORIZ_BORDER_CHAR

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

HEIGHT = args.first.nil? ? buffer.length : args.first.to_i

start_offset = [ 0, buffer.length - HEIGHT].max
screen = buffer[start_offset..-1]
if screen.length < HEIGHT
  (screen.length...HEIGHT).each do
    stage(screen, "")
  end
end

TITLE = "PTY SCREEN #{INNER_LINE_WIDTH}x#{HEIGHT}"

FRAME_BOTTOM = (" " * HORIZ_MARGIN) + BL_CHAR + (VERT_BORDER_CHAR * (WIDTH - 2)) + BR_CHAR
FRAME_TOP_LEFT = TL_CHAR + (VERT_BORDER_CHAR * (((WIDTH - TITLE.length - 2) / 2) - 2))
FRAME_TOP_RIGHT = (VERT_BORDER_CHAR * ((WIDTH - FRAME_TOP_LEFT.length - TITLE.length - 2) - 3)) + TR_CHAR

COLORIZED_TITLE = "\e[93m#{TITLE}\e[0m"

def vert_margin
  (0...VERT_MARGIN).each { print "\n" }
end

vert_margin
puts "#{" " * HORIZ_MARGIN}#{FRAME_TOP_LEFT}\u2524 #{COLORIZED_TITLE} \u251c#{FRAME_TOP_RIGHT}"
puts screen.join("\n")
puts FRAME_BOTTOM
vert_margin
