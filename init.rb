require 'reports_exceptions'

ActionController::Base.send :extend, ExceptionHandler::ReportsExceptions
