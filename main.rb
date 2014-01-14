#!/usr/bin/env ruby

# The Ruby Syslog Server
#
# Author:: Jonathan Gnagy (mailto:jonathan.gnagy@gmail.com)
# Copyright:: Copyright (c) 2010
# License:: Distributed under the GPLv3 ( http://www.gnu.org/licenses/gpl.html )
#
# Usage:
#   #!/usr/bin/env ruby
#   require 'parser'
#   require 'storage'
#   require 'server'
#   require 'yaml'
#  
#   config = YAML.load_file('config.yaml')
#  
#   server = RubySyslog::Server.new(config)
#   server.start
#  
#   while !server.stopped? or server.logs_queued? do
#     sleep(1)
#     server.process_logs
#   end
#  
#   server.shutdown

require_relative 'storage'
require_relative 'server'
require 'yaml'

config = YAML.load_file('config.yaml')

server = RubySyslog::Server.new(config)
#server.audit = true
server.start

while !server.stopped? or server.logs_queued? do
	sleep(1)
	server.process_logs
end

server.shutdown