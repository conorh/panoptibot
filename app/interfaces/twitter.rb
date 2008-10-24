require 'rubygems'
require 'twitter'

class TwitterInterface
  def run
    RAILS_DEFAULT_LOGGER.info("Starting Twitter Interface")

    Twitter::Client.configure do |conf|
      # We can set Twitter4R to use <tt>:ssl</tt> or <tt>:http</tt> to connect to the Twitter API.
      # Defaults to <tt>:ssl</tt>
      conf.protocol = :ssl

      # We can set Twitter4R to use another host name (perhaps for internal
      # testing purposes).
      # Defaults to 'twitter.com'
      conf.host = 'twitter.com'

      # We can set Twitter4R to use another port (also for internal
      # testing purposes).
      # Defaults to 443
      conf.port = 443

      # We can also change the User-Agent and X-Twitter-Client* HTTP headers
      conf.user_agent = 'Panoptibot'
      conf.application_name = 'Panoptibot'
      conf.application_version = 'v1.0'
      conf.application_url = 'http://github.com/conorh/panoptibot/tree/master'

      # Twitter (not Twitter4R) will have to setup a source ID for your application to get it
      # recognized by the web interface according to your preferences.
      # To see more information how to go about doing this, please referen to the following thread:
      # http://groups.google.com/group/twitter4r-users/browse_thread/thread/c655457fdb127032
      # conf.source = "your-source-id-that-twitter-recognizes"
    end

    @twitter = Twitter::Client.new(:login => APP_CONFIG[:twitter_account], :password => APP_CONFIG[:twitter_password])
    @twitter_account = APP_CONFIG[:twitter_account]

    @last_message = Message.find(:first, :conditions => ["sent_to = ?", "twitter:#{@twitter_account}"], :order => "created_at DESC" )

    while true
      messages = @twitter.messages(:received)

      if @last_message
        last_message_id = @last_message.reference.to_i
    
        messages.reject! {|m| m.id <= last_message_id}
      end

      for message in messages
        RAILS_DEFAULT_LOGGER.debug "Received direct message from #{message.sender.screen_name}: #{message.text}"
    
        @twitter.status(:post, "#{message.sender.screen_name}: #{message.text[0..(140 - message.sender.screen_name.length - 2 - 1)]}")   # -2 is for the ": ", -1 is for 0-based strings
        @last_message = Message.create(
          :user_id => 0,
          :nick => message.sender.screen_name,
          :im_userid => message.sender.screen_name,
          :body => message.text,
          :full_message => message.text,
          :sent_to => "twitter:#{@twitter_account}",
          :reference => message.id
        )
      end
      sleep 60
    end
  end
end
