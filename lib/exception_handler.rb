require 'net/smtp'

# Exception handler/reporter
module ExceptionHandler
  class Reporter

    def initialize(opts=nil)
      opts ||= {}
      @date = opts[:date] || (Time.now - (24 * 3600)).strftime("%Y-%m-%d")
      @mail_to = opts[:mail_to]
      @mail_from = opts[:mail_from] || 'exception_reporter'
      @subject = opts[:mail_subject] || "Exception Report"
      @controller_class = opts[:controller_class] || ApplicationController
      @hostname = opts[:hostname] || @controller_class.exception_hostname
      @exceptions_per_method = (opts[:exceptions_per_method] || 3).to_i
      @strip = (opts[:strip] || 2).to_i
      @verbose = opts[:verbose] || false
      @smtp_server = opts[:smtp_server] || 'localhost'
      @smtp_port = opts[:smtp_port] || 25
    end

    def run
      get_files_from_exception_dirs

      generate_html

      if @mail_to
        mail_html
      else
        @html
      end
    end

    def self.run(opts=nil)
      new(opts).run
    end

  private

    def get_files_from_exception_dirs
      @controller_class.exceptions_dir.each{|dir| process_dir(dir)}
    end

    def process_dir(dir)
      @ex2cat2list = {}
      Dir["#{dir}/[A-Z]*"].each do |ex|
        puts "Processing: #{ex}" if @verbose
        exception = ex.split('/').last.gsub('_','::')
        Dir["#{ex}/#{@date}/*/*"].each do |file|
          url = file_to_url(file)
          header = get_header(file)
          cat = get_category(header)

          @ex2cat2list[exception] ||= {:count => 0}
          @ex2cat2list[exception][:count] += 1
          @ex2cat2list[exception][:dir] ||= url.split('/')[0..-3].join('/')
          (@ex2cat2list[exception][cat] ||= []) << url

          puts "\t#{exception}[#{cat}] << #{url}" if @verbose
        end
      end
    end

    def file_to_url(file)
      "http://#{@hostname}/#{file.split('/', @strip + 1).last}"
    end

    def get_header(file)
      ret = ''
      File.new(file).each do |line|
        break if '----' == line[0,4]
        ret << line
      end
      ret = 'empty' unless ret.strip.size > 0
      ret
    end

    def get_category(text)
      text.scan(/occurred in ([^:]+)/).flatten.first || ''
    end

    def generate_html
      sorted_keys = @ex2cat2list.keys.sort_by{|ii| @ex2cat2list[ii][:count]}.reverse

      @html = []
      @html << "<html>"

      # emit header table
      @html << "<a name='top'/>"
      @html << "<table border='1' width='100%'>"
      @html << "<tr><th>Exception</th><th>Dir</th><th>Count</th></tr>"
      sorted_keys.each do |ex|
        cat2list = @ex2cat2list[ex]
        @html << "<tr><td><a href='##{ex}'>#{ex}</a></td><td><a href='#{cat2list[:dir]}/'>link</a><td>#{cat2list[:count]}</td></tr>"
      end
      @html << "</table>"

      # emit specific errors grouped by category
      sorted_keys.each do |ex|
        cat2list = @ex2cat2list[ex]
        keys = cat2list.keys.reject{|key| key.is_a?(Symbol)}

        @html << "<hr/>"
        @html << "<a name='#{ex}'>#{ex}</a> (<a href='#top'>top</a>)"
        @html << "<table border='1' width='100%'>"
        keys.sort_by{|ii| cat2list[ii].size}.reverse.each do |key|
          list = cat2list[key]
          @html << "<tr>"
            @html << "<td nowrap>#{key}&nbsp;</td>"
            @html << "<td>#{list.size}</td>"
            @html << "<td>"
              @html << list[0, @exceptions_per_method].map{|ii| "<a href='#{ii}'>#{ii.split('/').last}</a>"}.join('<br/>')
            @html << "</td>"
          @html << "</tr>"
        end
        @html << "</table>"
      end

      @html << "</html>"

      @html = @html.join("\n")

      puts "html:\n#{@html}" if @verbose
    end

    def mail_html
      puts "Mailing report to: #{@mail_to}..." if @verbose
      @header = "Subject: #{@subject}\n"
      @header << "Content-Type: text/html\n"
      Net::SMTP.start(@smtp_server, @smtp_port) do |smtp|
        smtp.send_message "#{@header}\n#{@html}.", @mail_from, @mail_to
      end
    end
  end

  module ReportsExceptions
    def saves_exceptions(opts={})
      self.send :include, InstanceMethods
      self.send(:rescue_from, Exception, :with => :rescue_all_exceptions)

      cattr_accessor :exceptions_dir, :exception_hostname, :do_on_exception, :exception_template
      cattr_accessor :only, :except, :log_when

      self.exception_hostname = opts[:hostname] || Socket.gethostname
      self.exceptions_dir     = opts[:exceptions_dir] || "#{RAILS_ROOT}/log/exceptions"
      self.exception_template = opts[:exception_template] || "exception_handler/exception_template.html.erb"
      self.only               = opts[:only] && [opts[:only]].flatten.map(&:to_sym)
      self.except             = opts[:except]
      self.log_when           = opts[:log_when]
    end

    module InstanceMethods

      def rescue_all_exceptions(exception)
        return if self.class.only and not self.class.only.include?(exception.class.name.to_sym)
        return if self.class.except and self.class.except.include?(exception.class.name.to_sym)
        if check_block(exception, &self.class.log_when)
          write_exception_to_file(exception)
        end
        rescue_action(exception)
      end

      def check_block(ex, &block)
        return true unless block
        InstanceMethods.module_eval{define_method(:my_instance_exec, &block)}
        ret = send(:my_instance_exec, ex)
        InstanceMethods.module_eval{remove_method(:my_instance_exec)} rescue nil
        ret
      end

      def write_exception_to_file(exception, template_file=self.class.exception_template)
        @exception_time = Time.now
        path = "#{self.class.exceptions_dir}/#{exception.class.to_s.gsub('::', '_')}/#{@exception_time.strftime('%F')}/#{@exception_time.strftime('%H')}"

        if not File.directory?(path)
          FileUtils.mkdir_p path
        end

        @exception = exception
        @exception_backtrace = sanitize_backtrace(exception.backtrace)
        @exception_hostname = self.class.exception_hostname
        @rails_root = rails_root

        open("#{path}/#{@exception_time.strftime("%Y-%m-%d_%H:%M:%S")}.#{@exception_time.to_i % 1000}.txt", "w") do |f|
          # prevent DoubleRenderException from ActionController
          f.write(render_to_string(:template => exception_template, :layout => false))
          erase_render_results
        end
      end

      def request_is_from_search_engine?
        request.env['HTTP_USER_AGENT'] =~ /google|ia_archiver/i
      end

      def rails_root
        @rails_root ||= Pathname.new(RAILS_ROOT).cleanpath.to_s
      end

      def sanitize_backtrace(trace)
        return '' if not trace
        re = Regexp.new(/^#{Regexp.escape(rails_root)}/)
        trace.map do |line|
          Pathname.new(line.gsub(re, "[RAILS_ROOT]")).cleanpath.to_s
        end
      end

    end
  end

end
