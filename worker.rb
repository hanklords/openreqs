$: << "./lib"

require './openreqs'

Qu::Worker.new.start
