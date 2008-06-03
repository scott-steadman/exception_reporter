require 'exception_handler'

ActionController::Base.send :extend, ExceptionHandler::ReportsExceptions
