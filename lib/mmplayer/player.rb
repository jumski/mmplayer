module MMPlayer

  # Wrapper for MPlayer functionality
  class Player

    # @param [Hash] options
    # @option options [String] :flags MPlayer command-line flags to use on startup
    def initialize(options = {})
      @mplayer_messages = []
      @flags = "-fixed-vo -idle"
      @flags += " #{options[:flags]}" unless options[:flags].nil?
    end

    # Play a media file
    # @param [String] file
    # @return [Boolean]
    def play(file)
      ensure_player(file)
      if @player.nil?
        false
      else
        @player.load_file(file)
        true
      end
    end

    # Is MPlayer active?
    # @return [Boolean]
    def active?
      !@player.nil? && !@player.stdout.gets.nil?
    end

    # Media progress information
    # eg {
    #  :length => 90.3,
    #  :percent => 44,
    #  :position => 40.1
    # }
    # Length and position are in seconds
    # @return [Hash, nil]
    def progress
      unless (time = poll_mplayer_progress).nil?
        time[:percent] = get_percentage(time)
        time
      end
    end

    # Shortcut to send a message to the MPlayer
    # @return [Object]
    def mplayer_send(method, *args, &block)
      if @player.nil? && MPlayer::Slave.method_defined?(method)
        # warn
      else
        send_mplayer_message { @player.send(method, *args, &block) }
      end
    end

    # Does the MPlayer respond to the given message?
    # @return [Boolean]
    def mplayer_respond_to?(method, include_private = false)
      (@player.nil? && MPlayer::Slave.method_defined?(method)) ||
        @player.respond_to?(method)
    end

    # Cause MPlayer to exit
    # @return [Boolean]
    def quit
      @player.quit
      @player_thread.kill
      true
    end

    private

    # Sweep for leftover/hanging message threads
    def sweep_messages
      if @mplayer_messages.empty?
        false
      else
        sleep(0.01)
        @mplayer_messages.each(&:kill)
        true
      end
    end

    # Send mplayer a message async
    def send_mplayer_message(&block)
      sweep_messages
      thread = Thread.new do
        begin
          yield
        rescue Exception => exception
          Thread.main.raise(exception)
        end
      end
      thread.abort_on_exception = true
      @mplayer_messages << thread
      thread
    end

    # Get progress percentage from the MPlayer report
    def get_percentage(report)
      percent = (report[:position] / report[:length]) * 100
      percent.round
    end

    # Poll MPlayer for progress information
    def poll_mplayer_progress
      time = nil
      send_mplayer_message do
        time = {
          :length => get_mplayer_float("time_length"),
          :position => get_mplayer_float("time_pos")
        }
      end
      time
    end

    # Poll a single MPlayer value for the given key
    def get_mplayer_float(key)
      @player.get(key).strip.to_f
    end

    # Ensure that the MPlayer process is invoked
    # @param [String] file The media file to invoke MPlayer with
    # @return [MPlayer::Slave]
    def ensure_player(file)
      if @player.nil? && @player_thread.nil?
        @player_thread = Thread.new do
          begin
            @player = MPlayer::Slave.new(file, :options => @flags)
          rescue Exception => exception
            Thread.main.raise(exception)
          end
        end
        @player_thread.abort_on_exception = true
      end
    end

  end

end
