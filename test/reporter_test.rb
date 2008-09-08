require File.dirname(__FILE__) + '/../../../../config/environment'
require 'test/unit'
require 'action_controller/test_process'
require 'fileutils'
require 'mocha'

require 'reporter'

class TestController < ActionController::Base
  ActionController::Routing::Routes.draw do |map|
    map.raise '/raise', :controller=>'test', :action=>'do_raise'
  end
  def do_raise
    raise params[:ex].constantize.new(params[:msg])
  end
end


class ReporterTest < Test::Unit::TestCase

  EXCEPTIONS_DIR = (ENV['TEMP'] || ENV['TMP'] || '.') + '/tmp/exceptions'

  def setup
    @controller = TestController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    FileUtils.mkdir_p(EXCEPTIONS_DIR)
    @today = Date.today.strftime("%Y-%m-%d")
  end

  def teardown
    FileUtils.rm_rf(EXCEPTIONS_DIR)
  end


  def test_date_default
    reporter = ExceptionHandler::Reporter.new
    assert_equal Date.yesterday.strftime('%Y-%m-%d'), reporter.send(:date)
  end

  def test_date_with_date_option
    expected = '1994-09-10'
    reporter = ExceptionHandler::Reporter.new(:date=>expected)
    assert_equal expected, reporter.send(:date)
  end

  def test_date_with_minutes_ago_option
    reporter = ExceptionHandler::Reporter.new(:minutes_ago=>1)
    assert_equal Date.today.strftime('%Y-%m-%d'), reporter.send(:date)
  end


  def test_time_default
    reporter = ExceptionHandler::Reporter.new
    assert_equal '00:00:00', reporter.send(:time)
  end

  def test_time_with_date_option
    reporter = ExceptionHandler::Reporter.new(:date=>'ignored')
    assert_equal '00:00:00', reporter.send(:time)
  end

  def test_time_with_minutes_ago_option
    expected = (Time.now - 5.minutes).strftime('%H:%M:00')
    reporter = ExceptionHandler::Reporter.new(:minutes_ago=>5)
    assert_equal expected, reporter.send(:time)
  end


  def test_matches_time_true
    dir, file = exception_dir_and_file(String.new, Time.now - 5.minutes)
    reporter = ExceptionHandler::Reporter.new(:minutes_ago=>5)
    assert_equal true, reporter.send(:matches_time?, file)
  end

  def test_matches_time_false
    dir, file = exception_dir_and_file(String.new, Time.now - 6.minutes)
    reporter = ExceptionHandler::Reporter.new(:minutes_ago=>5)
    assert_equal false, reporter.send(:matches_time?, file)
  end


  def test_reporter_no_mail_to
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'

    html = ExceptionHandler::Reporter.run(:hostname=>'foo', :date=>@today, :controller_class=>TestController)

    assert_match 'RuntimeError', html
    assert_match 'test#do_raise', html
    assert_match "http://foo/exceptions/RuntimeError/#{@today}", html
  end

  def test_reporter_with_mail_to
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR)
    get :do_raise, :ex=>'RuntimeError', :msg=>'test exception'

    Net::SMTP.any_instance.expects(:start)
    ExceptionHandler::Reporter.run(:mail_to=>'foo@bar.com', :hostname=>'foo', :date=>@today, :controller_class=>TestController)
  end

  def test_reporter_excludes_files_before_minutes_ago
    TestController.saves_exceptions(:exceptions_dir=>EXCEPTIONS_DIR)
    dir, file = exception_dir_and_file(String.new, Time.now - 6.minutes)
    FileUtils.mkdir_p(dir)
    FileUtils.touch(dir + file)
    dir, file = exception_dir_and_file(Hash.new, Time.now - 4.minutes)
    FileUtils.mkdir_p(dir)
    FileUtils.touch(dir + file)

    html = ExceptionHandler::Reporter.run(:hostname=>'foo', :minutes_ago=>5, :controller_class=>TestController)

    assert_no_match %r{String}, html
    assert_match 'Hash', html
    assert_no_match %r{http://foo/exceptions/String}, html
    assert_match "http://foo/exceptions/Hash/#{@today}", html
  end


private

  def dir(name)
    "#{EXCEPTIONS_DIR}/#{name}"
  end

  def exception_dir_and_file(ex, time=Time.now)
    [
      "#{dir(ex.class.to_s.gsub('::', '_'))}/#{time.strftime('%F')}/#{time.strftime('%H')}/" ,
      "#{time.strftime("%Y-%m-%dT%H:%M:%S")}.#{time.to_i % 1000}.txt"
    ]
  end

end
