require 'pty'
require 'io/console'

master, slave = PTY.open

master.autoclose = true
orig_stdout = $stdout.clone
$stdout.reopen(slave)

puts "hi"

$stdout.reopen(orig_stdout)

begin
  while output = master.read_nonblock(1024)
    puts output
  end
rescue IO::EAGAINWaitReadable => e
  # We've hit the end of the sream
end

slave.close
master.close
