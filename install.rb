require 'fileutils'
target_path = File.expand_path(File.dirname(__FILE__) + '/../../../app/views/exception_handler/')
puts "Copying: exception_template.html.erb to #{target_path}/"
FileUtils.mkdir_p(target_path)
FileUtils.cp "#{File.dirname(__FILE__)}/app/views/exception_handler/exception_template.html.erb", target_path
