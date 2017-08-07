# this program was to test whether cursor save and restore took into account newlines printed since
# the last save.
#
# it doesn't.

puts "hi"
print "\e[s"
puts "sup"
print "\e[u"
# at this point, if newlines are accounted for, we should be at the beginning of "sup". if newlines
# aren't accounted for, we'll be at the newline printed at the end of "sup", assuming all of this is
# at the bottom of the terminal and new output causes scrolling.
sleep 2
puts "yo"

# if newlines are accounted for, output will look like:
#   hi
#   yop
#
# if newlines aren't accounted for, output will look like:
#   hi
#   sup
#   yo
