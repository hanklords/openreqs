lib = File.expand_path('../lib', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
require 'openreqs'

class Openreqs
  run!
end
