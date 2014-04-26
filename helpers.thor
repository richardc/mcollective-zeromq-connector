#
# Making demo environments is a bit fiddly as you have to set up a config file
# for each role, and foreman doesn't paramterise nicely, so generate the
# entire thing

class Helpers < Thor
  desc "make_demo DIRECTORY", "makes a demo in a directory"
  method_option :mcollective,
                :default => Pathname.new('~/src/mcollective').expand_path.to_s,
                :desc => "Where to find an MCollective checkout"

  method_option :number_of_servers,
                :aliases => %w[ n ],
                :type => :numeric,
                :default => 5,
                :desc => 'How many servers to make'

  method_option :curve,
                :type => :boolean,
                :default => true,
                :desc => 'Set up curve?'

  def make_demo(directory)
    directory = Pathname.new(directory)
    puts "making a demo in '#{directory}' with #{options[:number_of_servers]} servers"
    directory.mkpath

    roles = []
    roles << 'middleware'
    roles << 'client'
    options[:number_of_servers].times do |i|
      roles << "server-#{i}"
    end

    make_procfile(directory, options, roles)

    roles.each do |node|
      if options[:curve]
        # generate curve key
        puts "keypair for #{node}"
        `bin/generate_keypair #{directory + node}`
      end

      make_mcollective_config(directory, options, node)
    end

    make_client(directory, options)
  end

  private

  # foreman is another fine application which follows the ruby 'style' of
  # having it's project name and main config file have distinct names (yes
  # bundler, I'm looking at you)
  def make_procfile(directory, options, roles)
    pwd = Pathname.pwd
    File.open(directory + 'Procfile', 'w') do |file|
      roles.each do |role|
        case role
        when 'middleware'
          if options[:curve]
            file.puts "middleware: #{pwd + 'bin/middleware'} middleware.private"
          else
            file.puts "middleware: #{pwd + 'bin/middleware'}"
          end
        when /^server-/
          file.puts "#{role}: ruby -I #{options[:mcollective]}/lib #{options[:mcollective]}/bin/mcollectived --config #{role}.cfg"
        end
      end
    end
  end

  def make_mcollective_config(directory, options, node)
    # don't need an MCollective here
    return if node == 'middleware'

    pwd = Pathname.pwd
    File.open(directory + "#{node}.cfg", 'w') do |file|
      file.puts """
daemonize = false

libdir = #{options[:mcollective]}/plugins
libdir = #{pwd}/lib
logger_type = console
loglevel = debug
plugin.psk = pies

identity = #{node}

connector = zeromq
plugin.zeromq.pub_endpoint = tcp://127.0.0.1:61615
plugin.zeromq.sub_endpoint = tcp://127.0.0.1:61616
        """
      if options[:curve]
        file.puts """
plugin.zeromq.curve.enabled = true
plugin.zeromq.curve.middleware_public_key = middleware.public
plugin.zeromq.curve.public_key  = #{node}.public
plugin.zeromq.curve.private_key = #{node}.private
        """
      else
        # still have to say no to curve
        file.puts "plugin.zeromq.curve.enabled = false"
      end
    end
  end

  def make_client(directory, options)
    mco = directory + 'mco'
    File.open(mco, 'w') do |file|
      file.puts "#!/bin/bash"
      file.puts "exec ruby -I #{options[:mcollective]}/lib #{options[:mcollective]}/bin/mco \"$@\" --config client.cfg"
    end
    mco.chmod(0755)
  end
end