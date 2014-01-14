module RubySyslog
  require 'gserver'
  require 'resque'
  require_relative 'logqueue'
  require_relative 'lib/threadpool'
  
  DEFAULT_SERVER_CONFIG = {
	:protocol	=> 'tcp',
	:port		=> 9514
  }
  
  class Server < GServer
	# Allows for altering the config
	attr_accessor :config
	
	# Allows debug output to be specified later
    attr_accessor :verbose
	
	# Here are the logs waiting to be processed
	attr_accessor :log_queue
  
	# Initializes the server, sets up the configuration for all required classes,
	# loads all models, loads Storage, LogQueue, process ThreadPool, storage ThreadPool,
	# LogMutex (semaphore), and start the UDP and TCP listeners
	def initialize(config = DEFAULT_SERVER_CONFIG, *args)
		@config = config
		@log_queue = LogQueue.new
		puts "Log Queue loaded          [  OK  ]" if config[:verbose]
		@mutex = LogMutex.new
		puts "Log Mutex loaded          [  OK  ]" if config[:verbose]
		
		@queue_flushed = true
		
		listen_for_udp if @config[:protocol].match(/^([bB]oth|UDP|udp)$/)
		
		puts "Server loaded             [  OK  ]" if config[:verbose]
		super(config[:port], *args) if @config[:protocol].match(/^([bB]oth|TCP|tcp)$/)
	end
	
	# The TCP listener method. This is what's performed for each TCP connection
	def serve(io)
		while io.gets do
			break if /^quit[^\w]/.match($_.to_s)
			payload = $_
			tcp = Thread.new { enqueue_log payload }
		end
	end
	
	# The UDP listener method. This fires off a separate thread to catch UDP packets
	# and queue them up for processing and storage. Returns +true+ if starting the UDP
	# listener was successful.
	def listen_for_udp
		begin
			udp_thread = Thread.new do
				udp_socket = UDPSocket.new
				udp_socket.bind( "0.0.0.0", @config[:port])
				loop do
					payload = udp_socket.recvfrom( 1024 )[0]
					break if /^quit[^\w]/.match(payload.to_s)
					unless payload.empty?
						udp = Thread.new { enqueue_log payload }
					end
				end
			end
			return true
		rescue
			return false
		end
	end
	
	# This methods tells the server to pull all logs from the LogQueue and 'process' them.
	# Essentially, this moves logs from the incoming LogQueue to the storage_queue in a
	# Redis database for background processing. Each job parses the syslog payload and then
	# saves it to a database.
	def process_logs
		until @log_queue.empty?
			@queue_flushed = false if @queue_flushed
			log = pop_log
			Resque.enqueue(Storage, log)
		end
		if !@queue_flushed
			puts "Log Queue Flush Complete @ #{Time.now}" if @config[:verbose] and !logs_queued?
			@queue_flushed = true
		end
	end
	
	# Utilizes the LogMutex to synchronize initial storage of log packets in the LogQueue
	def enqueue_log(log_data)
		@mutex.synchronize { @log_queue.push log_data }
	end
	
	# Utilizes the LogMutex to synchronize removing log packets from the LogQueue
	def pop_log
		return @mutex.synchronize { @log_queue.pop }
	end
	
	# Utilizes the LogMutex to synchronize checking how many logs are currently queued in the
	# LogQueue.
	def logs_queued?
		return @mutex.synchronize { @log_queue.size > 0 }
	end
  end
end