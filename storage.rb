class Storage
	require         "rubygems"
    require         "yaml"
    require         "active_record"
	require_relative 'lib/syslogproto'

	DEFAULT_STORAGE_CONFIG = {
		'development' => {
			'adapter'	=> 'sqlite3',
			'database'	=> 'db/development.sqlite3',
			'pool'		=>	5,
			'timeout'	=>	5000
		}
    }  

  	@queue = "storage_queue"
	
	# Loads the database config, connects to the database, parses the syslog packet and saves the data to the database
	# Executed by a worker in the background from a backend Redis database using Resqueue 
	def self.perform(packet)
		begin	
			@config = YAML.load_file('config.yaml')
		rescue
			puts "Warning! Error in loading config.yaml...Using default database config."
			@config = {:db => DEFAULT_STORAGE_CONFIG}
		end

		@loaded_models = []
		models = Dir.new("models/").entries.sort.delete_if { |ext| !(ext =~ /.rb$/) }
      
		# load the models
		models.each do |model|
			require_relative "models/#{model}"
			if @verbose
				puts "Loaded Model: #{model}"
			end # if debug
			@loaded_models << model
		end # models.each

		begin
			ActiveRecord::Base.establish_connection(@config[:db])
		rescue
			puts "Failed to establish connection with database. Retrying..."
			sleep(1)
			retry	
		end
		
		log = SyslogProto.parse(packet)
		new_log = Log.new(
			:hostname	=> log.hostname,
			:msg		=> log.msg,
			:facility	=> log.facility,
			:severity	=> log.severity
		)
		begin
			new_log.save
		rescue
			puts "Saving log #{log.object_id.to_s(16)} failed. Retrying..."
			sleep(1)
			retry
		ensure
			ActiveRecord::Base.connection.close
		end
	end # self.perform
  end # class Storage