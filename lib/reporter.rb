require 'net/smtp'

module ExceptionHandler
  class Reporter

    attr_reader :opts

    def initialize(opts=nil)
      @opts = opts || {}
    end

    def run
      get_files_from_exception_dirs
      if mail_to
        mail_html
      else
        html
      end
    end

    def self.run(opts=nil)
      new(opts).run
    end

  private

    def date
      @date ||=
        if opts[:minutes_ago]
          (Time.now - (60 * opts[:minutes_ago].to_i)).strftime('%Y-%m-%d')
        else
          opts[:date] || (Time.now - (24 * 3600)).strftime('%Y-%m-%d')
        end
    end

    def time
      @time ||=
        if opts[:minutes_ago]
          (Time.now - 60 * opts[:minutes_ago].to_i).strftime('%H:%M:00')
        else
          '00:00:00'
        end
    end

    def mail_to
      @mail_to ||= opts[:mail_to]
    end

    def mail_from
      @mail_from ||= opts[:mail_from] || 'exception_reporter'
    end

    def subject
      @subject ||= opts[:mail_subject] || 'Exception Report'
    end

    def controller_class
      @controller_class ||= opts[:controller_class] || ApplicationController
    end

    def hostname
      @hostname ||= opts[:hostname] || controller_class.exception_hostname
    end

    def exceptions_per_method
      @exceptions_per_method ||= (opts[:exceptions_per_method] || 3).to_i
    end

    def strip
      @strip ||= (opts[:strip] || 2).to_i
    end

    def verbose
      @verbose ||= opts[:verbose] || false
    end

    def smtp_server
      @smtp_server ||= opts[:smtp_server] || 'localhost'
    end

    def smtp_port
      @smtp_port ||= opts[:smtp_port] || 25
    end

    def get_files_from_exception_dirs
      controller_class.exceptions_dir.each{|dir| process_dir(dir)}
    end

    def process_dir(dir)
      @ex2cat2list = {}
      Dir["#{dir}/[A-Z]*"].each do |ex|
        puts "Processing: #{ex}" if verbose
        exception = ex.split('/').last.gsub('_','::')
        exception_files_for(ex).each do |file|
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

    def exception_files_for(ex)
      Dir["#{ex}/#{date}/*/*"].select{|ii| matches_time?(ii)}
    end

    # file name sample: 2008-09-06T02-51-45.705.txt
    def matches_time?(file)
      file.scan(/T(\d\d:\d\d:\d\d)/)[0][0] >= time
    end

    def file_to_url(file)
      "http://#{hostname}/#{file.split('/', strip + 1).last}"
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

    def html
      @html ||= begin
        sorted_keys = @ex2cat2list.keys.sort_by{|ii| @ex2cat2list[ii][:count]}.reverse

        html = []
        html << "<html>"

        # emit header table
        html << "<a name='top'/>"
        html << "<table border='1' width='100%'>"
        html << "<tr><th>Exception</th><th>Dir</th><th>Count</th></tr>"
        sorted_keys.each do |ex|
          cat2list = @ex2cat2list[ex]
          html << "<tr><td><a href='##{ex}'>#{ex}</a></td><td><a href='#{cat2list[:dir]}/'>link</a><td>#{cat2list[:count]}</td></tr>"
        end
        html << "</table>"

        # emit specific errors grouped by category
        sorted_keys.each do |ex|
          cat2list = @ex2cat2list[ex]
          keys = cat2list.keys.reject{|key| key.is_a?(Symbol)}

          html << "<hr/>"
          html << "<a name='#{ex}'>#{ex}</a> (<a href='#top'>top</a>)"
          html << "<table border='1' width='100%'>"
          keys.sort_by{|ii| cat2list[ii].size}.reverse.each do |key|
            list = cat2list[key]
            html << "<tr>"
              html << "<td nowrap>#{key}&nbsp;</td>"
              html << "<td>#{list.size}</td>"
              html << "<td>"
                html << list[0, exceptions_per_method].map{|ii| "<a href='#{ii}'>#{ii.split('/').last}</a>"}.join('<br/>')
              html << "</td>"
            html << "</tr>"
          end
          html << "</table>"
        end

        html << "</html>"

        html = html.join("\n")

        puts "html:\n#{html}" if verbose
        html
      end
    end

    def mail_html
      puts "Mailing report to: #{mail_to}..." if verbose
      header = "Subject: #{subject}\n"
      header << "Content-Type: text/html\n"
      Net::SMTP.start(smtp_server, smtp_port) do |smtp|
        smtp.send_message "#{header}\n#{html}.", mail_from, mail_to
      end
    end
  end
end
