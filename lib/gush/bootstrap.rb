require 'gush'

path = Gush.configuration.workflows_path
if path.nil?
  puts "Please specify Ruby file with workflows through :workflows_path option"
  exit
end

load path

puts "Sidekiq workers started"
