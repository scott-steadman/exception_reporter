module ExceptionHandler
  module ReportsExceptions
    def saves_exceptions(opts={})
      self.send :include, InstanceMethods
      self.send(:rescue_from, Exception, :with => :rescue_all_exceptions) if self.respond_to?(:rescue_from)


      cattr_accessor :exceptions_dir, :exception_hostname, :do_on_exception, :exception_template
      cattr_accessor :only, :except, :log_when

      self.exception_hostname = opts[:hostname] || Socket.gethostname
      self.exceptions_dir     = opts[:exceptions_dir] || "#{RAILS_ROOT}/log/exceptions"
      self.exception_template = opts[:exception_template] || "#{RAILS_ROOT}/app/views/exception_handler/exception_template.html.erb"
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
        time = Time.now
        path = "#{self.class.exceptions_dir}" <<
                "/#{exception.class.to_s.gsub('::', '_')}" <<
                "/#{time.strftime('%F')}" <<
                "/#{time.strftime('%H')}"

        if not File.directory?(path)
          FileUtils.mkdir_p path
        end

        # used by template
        @exception = exception
        @exception_time = time
        @exception_backtrace = sanitize_backtrace(exception.backtrace)
        @exception_hostname = self.class.exception_hostname
        @rails_root = rails_root

        open("#{path}/#{time.strftime("%Y-%m-%dT%H:%M:%S")}.#{time.to_i % 1000}.txt", "w") do |f|
          if (respond_to?(:render_to_string))
            # prevent DoubleRenderException from ActionController
            f.write(render_to_string(:file => exception_template, :layout => false))
            erase_render_results
          else
            f.write(ERB.new(template).result(binding))
          end
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
