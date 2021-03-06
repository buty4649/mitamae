# Wrapper of Specinfra used by not only ResourceExecutor but also MItamae::Node.
module MItamae
  class Backend
    CommandExecutionError = Class.new(StandardError)

    def initialize(options = {})
      @shell = options.fetch(:shell, '/bin/sh')
      @backend = Specinfra::Backend::Exec.new(shell: @shell)
    end

    # https://github.com/itamae-kitchen/itamae/blob/v1.9.9/lib/itamae/backend.rb#L46-L86
    def run_command(commands, options = {})
      options = { error: true }.merge(options)

      command_for_display = build_command(commands, options)
      MItamae.logger.debug "Executing `#{command_for_display}`..."

      stdout, stderr, status = run_with_open3(commands, options)

      MItamae.logger.with_indent do
        flush_buffers(stdout, stderr)

        if status.exitstatus == 0 || !options[:error]
          method = :debug
          message = "exited with #{status.exitstatus}"
        else
          method = :error
          message = "Command `#{command_for_display}` failed. (exit status: #{status.exitstatus})"

          unless MItamae.logger.level == Logger::DEBUG
            stdout.each_line do |l|
              log_output_line("stdout", l)
            end
            stderr.each_line do |l|
              log_output_line("stderr", l)
            end
          end
        end
        MItamae.logger.send(method, message)
      end

      if options[:error] && status.exitstatus != 0
        raise CommandExecutionError
      end

      Specinfra::CommandResult.new(stdout: stdout, stderr: stderr, exit_status: status.exitstatus)
    end

    def get_command(*args)
      @backend.command.get(*args)
    end

    def host_inventory
      @backend.host_inventory
    end

    private

    def flush_buffers(stdout, stderr)
      unless stdout.empty?
        MItamae.logger.debug("stdout | #{stdout}")
      end
      unless stderr.empty?
        MItamae.logger.debug("stderr | #{stderr}")
      end
    end

    def log_output_line(output_name, line)
      line = line.gsub(/[[:cntrl:]]/, '')
      MItamae.logger.error("#{output_name} | #{line}")
    end

    # https://github.com/itamae-kitchen/itamae/blob/v1.9.9/lib/itamae/backend.rb#L168-L189
    def build_command(commands, options)
      if commands.is_a?(Array)
        command = Shellwords.shelljoin(commands)
      else
        command = commands
      end

      cwd = options[:cwd]
      if cwd
        command = "cd #{cwd.shellescape} && #{command}"
      end

      user = options[:user]
      if user
        command = "cd ~#{user.shellescape} ; #{command}"
        command = "sudo -H -u #{user.shellescape} -- #{@shell.shellescape} -c #{command.shellescape}"
      end

      command
    end

    def run_with_open3(commands, options)
      if options[:user]
        # Cannot emulate `:user` option without the shell. Fallback to the slow version.
        Open3.capture3(@shell, '-c', build_command(commands, options))
      else
        if commands.is_a?(String)
          commands = [@shell, '-c', commands]
        end

        spawn_opts = {}
        cwd = options[:cwd]
        if cwd
          spawn_opts[:chdir] = cwd
        end

        Open3.capture3(*commands, spawn_opts)
      end
    end
  end
end
