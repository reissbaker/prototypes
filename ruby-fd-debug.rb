device = ARGV.first
file = File.open(device)
io = IO.for_fd(file.fileno)
puts "output: #{io.gets(nil)}"
