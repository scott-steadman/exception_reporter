require 'rubygems'
require 'rake'

desc "Generate and mail Exception Report [mail_to=email]"
task :generate_exception_report => :environment do
  puts ExceptionHandler::Reporter.run(
    :date => ENV['date'],
    :mail_to => ENV['mail_to'],
    :mail_from => ENV['mail_from'],
    :mail_subject => ENV['mail_subject'],
    :hostname => ENV['hostname'],
    :exceptions_per_method => ENV['exceptions_per_method'],
    :strip => ENV['strip'],
    :verbose => ENV['verbose']
  )
end
