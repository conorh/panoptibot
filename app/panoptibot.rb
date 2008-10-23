#!/usr/bin/env ruby
require File.expand_path(File.dirname(__FILE__) + "/../config/environment")

require 'xmpp4r-simple'
require 'yaml'
require 'logger'

BASE_URL = "http://someserver/bot/messages" unless Object.const_defined? :BASE_URL
BOT_NAME = "panoptibot" unless Object.const_defined? :BOT_NAME

if ENV['HOME'] && File.exist?(File.join(ENV['HOME'], '.panoptibot.yml'))
  config_file = File.join(ENV['HOME'], '.panoptibot.yml')
else
  config_file = File.join(RAILS_ROOT, 'config', 'bots.yml')
end
bot_config = YAML.load_file(config_file)[RAILS_ENV].symbolize_keys

@jabber = Jabber::Simple.new(bot_config[:username], bot_config[:password])

HELP_MESSAGE = "commands are /hist [1,1..100], /nick [new nick name], /who, /quiet, /resume, /search [string]"
SEND_MESSAGE_STATUSES = ['online', 'dnd', 'away', 'ghost']

def can_send_message?(status)
  SEND_MESSAGE_STATUSES.include?(status.to_s)
end

def online_users
 User.find(:all, :conditions => ["status IN (?)", SEND_MESSAGE_STATUSES])
end

def bot_user
  bot ||= User.new(:login => BOT_NAME, :nick => BOT_NAME)
end

def parse_command(message, user)
  # if the message starts with a / and has the format '/command option'
  if(message =~ /^(\/.*?)(?:\s|$)(.*)/ )
    case $1
      when "/kill"
        exit(1)
      when "/add"
        if($2 and $2.length >= 3)
          result = add_user($2)
          send_message(user, "added #{$2} - #{result ? "success" : "failed"}")
        end
      when "/remove"
        if($2 and $2.length >= 3)        
          result = remove_user($2)
          send_message(user, "removed #{$2} - #{result ? "success" : "failed"}")
        end
      when "/help"
        send_message(user, HELP_MESSAGE)
      when "/h","/hist","/history"
        history = Message.history($2).collect {|m| m.to_s }   
        send_message(user, "Full history at: #{BASE_URL}/messages\n#{history.join("\n")}")
      when "/n","/nick","/nickname"
        unless $2.blank?
          user.update_attribute(:nick, $2)
          send_message(user, "nickname updated to '#{$2}'")
        end
      when "/w","/who"
        users = online_users.collect {|u| u.nick || u.login }
        send_message(user, "online now - #{users.join(", ")}")
      when "/q","/quiet"
        user.update_attribute(:status, 'no_messages')
        send_message(user, "status set to quiet, you will not receive messages until you send a /resume command")
      when "/r","/resume"
        user.update_attribute(:status, 'online')
        send_message(user, "status set to online, you will receive messages now")
      when "/s","/search"
        if($2 and $2.length >= 3)
          match_string = $2
          history = Message.find(:all, :conditions => ["body LIKE ?", '%' + match_string + '%'], :limit => 20)
          send_message(user, "#{history.length} lines of history matching '#{match_string}'")
        end
      else
        send_message(user, "unrecognized command")
    end
    return true
  else
    return false
  end
end

def add_user(user_id)
  match = user_id.match(/^(.*?)@/)
  nick = match[1] if match  
  
  user = User.new(:login => user_id, :nick => nick, :email => user_id, :password => user_id, :password_confirmation => user_id)
  
  if(user.save)
    @jabber.add(user_id)    
    send_message(user, "Hello komrade! Welcome to #{BOT_NAME} /help for help")
    send_message(user, "History at #{BASE_URL}/messages or use the /hist command")
    users = online_users.collect {|u| u.nick || u.login }
    send_message(user, "Currently online: #{users.join(", ")}")
    return true
  else
    return false
  end
end

def remove_user(user_id)
  user = User.find_by_login(user_id)
  if user
    user.destroy
    @jabber.remove(user_id)
    return true
  else
    return false
  end
end

def send_message(to, body, from = nil)
  from ||= bot_user
  to = to.login if to.respond_to? :login
  
  message = Jabber::Message.new
  message.body = "#{from.nick}: #{body}"
  message.type = :chat
  
  # Create the html part of the message (with bolded name)
  h = REXML::Element::new("html")
  h.add_namespace('http://jabber.org/protocol/xhtml-im')
  b = REXML::Element::new("body")
  b.add_namespace('http://www.w3.org/1999/xhtml')
  t = REXML::Text.new("<strong>#{from.nick}:</strong> #{body.gsub("\n", "<br/>")}", false, nil, true, nil, %r/.^/ )
  b.add(t)
  h.add(b)
  message.add_element(h)
  @jabber.deliver(to, message)
end

if STDIN.isatty
  logger = Logger.new(STDERR)
  if RAILS_ENV == "production"
    logger.level = Logger::INFO
  else
    logger.level = Logger::DEBUG
  end
  Object.send :remove_const, :RAILS_DEFAULT_LOGGER
  Object.const_set :RAILS_DEFAULT_LOGGER, logger
  RAILS_DEFAULT_LOGGER.info("Starting Panoptibot")
end

##################
# Main server loop
##################
while true
  ActiveRecord::Base.verify_active_connections!

  begin
    while @jabber.connected? != true
      RAILS_DEFAULT_LOGGER.info("Panoptibot: Disconnected - trying to reconnect")
      @jabber.connect
      sleep 30 unless jabber.connected?
    end
    
    @jabber.received_messages do |msg|
      RAILS_DEFAULT_LOGGER.debug("Panoptibot: Message (#{msg.type}) from from #{msg.from.strip.to_s}")
      next unless msg.type == :chat
    
      from_user = User.find_by_login(msg.from.strip.to_s)
      RAILS_DEFAULT_LOGGER.debug("  Unknown Sender!!!") unless from_user
      next unless from_user
      
      unless can_send_message?(from_user.status)
        RAILS_DEFAULT_LOGGER.debug "  User was not known to be online, marking as 'ghost'"
        from_user.status = 'ghost'   # sometimes users won't send presence updates but still be online
        from_user.save
      end
    
      next if parse_command(msg.body, from_user)
      Message.new(:body => msg.body, :nick => from_user.nick, :im_userid => msg.from.strip.to_s, :user => from_user).save
      
      RAILS_DEFAULT_LOGGER.debug("  broadcasting the message")
      online_users.each do |u|
        next if u.login == from_user.login # don't send the message to the originating user
        RAILS_DEFAULT_LOGGER.debug("    to #{u.login}")
        send_message(u, msg.body, from_user)
      end
    end
  
    @jabber.new_subscriptions do |user_id, presence|
      user_id = user_id.jid.to_s
      RAILS_DEFAULT_LOGGER.info("Panoptibot: new user req - #{user_id}")
    
      # Add a user only if they are in the DB
      add_user(user_id) if(User.find_by_login(user_id))
    end
  
    @jabber.subscription_requests do |user_id, presence|
      RAILS_DEFAULT_LOGGER.info("Panoptibot: sub request from #{user_id}: #{presence}")
    
      # Add a user only if they are in the DB
      add_user(user_id) if(User.find_by_login(user_id))
    end 
  
    @jabber.presence_updates do |user_id, new_presence|
      RAILS_DEFAULT_LOGGER.info("Panoptibot: presence update #{user_id} - #{new_presence}")

      from_user = User.find_by_login(user_id)
      remove_user(user_id) unless from_user

      if from_user and from_user.status != 'no_messages'
         old_presence = from_user.status
         from_user.update_attribute(:status, new_presence)

         RAILS_DEFAULT_LOGGER.info("Panoptibot: presence update success #{user_id} - #{new_presence}")
       
         if(old_presence == 'unavailable' and can_send_message?(new_presence))
           users = online_users.collect {|u| u.nick || u.login }
           send_message(user_id, "Hello komrade, I am currently monitoring: #{users.join(", ")}")
           send_message(user_id, "History at #{BASE_URL}/messages or /h")
           send_message(user_id, "Last 10 messages")
           message = Messages.history(10).collect {|m| m.to_s }.join("\n")
           send_message(user_id, message)
         end
      end
    end  
  
    sleep 2
  rescue StandardError => e
    RAILS_DEFAULT_LOGGER.debug("Panoptibot error: #{e.message}\n#{e.backtrace.join("\n")}")
  end
end
