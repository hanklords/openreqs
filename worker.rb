$: << "./lib"

require './openreqs'

puts "Jobs queue length : #{Qu.length}"

Qu.logger.level = Logger::DEBUG
Qu::Worker.new.start
