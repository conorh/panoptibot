#!/usr/bin/env ruby
require File.expand_path(File.dirname(__FILE__) + "/../config/environment")

require 'xmpp4r-simple'
require 'yaml'
require 'logger'

BASE_URL = "http://chambers.streeteasy.com/streetbot/messages"
BOT_NAME = "streetbot"

bot_config = YAML.load_file(RAILS_ROOT + '/config/bots.yml')[RAILS_ENV].symbolize_keys
@jabber = Jabber::Simple.new(bot_config[:username], bot_config[:password])

HELP_MESSAGE = "commands are /hist [1,1..100], /nick [new nick name], /who, /quiet, /resume, /search [string]"
SEND_MESSAGE_STATUSES = ['online', 'dnd', 'away']

def can_send_message?(status)
  SEND_MESSAGE_STATUSES.include?(status.to_s)
end

def online_users
 User.find(:all, :conditions => ["status IN (?)", SEND_MESSAGE_STATUSES])
end

def bot_user
  bot ||= User.new(:login => BOT_NAME, :nick => BOT_NAME)
end

def log(message)
  @logger ||= Logger.new(RAILS_ROOT + "/log/bot-#{RAILS_ENV}.log")
  @logger.info("[#{Time.now}] #{message}")
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
  @jabber.deliver(to.login, message)
end


##################
# Main server loop
##################
while true
  ActiveRecord::Base.verify_active_connections!

  begin
    while @jabber.connected? != true
      log("disconnected - trying to recconect")
      @jabber.connect
      sleep 30 unless jabber.connected?
    end
    
    @jabber.received_messages do |msg|
      next unless msg.type == :chat
    
      from_user = User.find_by_login(msg.from.strip.to_s)
      next unless from_user
    
      next if parse_command(msg.body, from_user)
      Message.new(:body => msg.body, :nick => from_user.nick, :im_userid => msg.from.strip.to_s, :user => from_user).save
    
      online_users.each do |u|
        next if u.login == from_user.login # don't send the message to the originating user
        send_message(u, msg.body, from_user)
      end
    end
  
    @jabber.new_subscriptions do |user_id, presence|
      user_id = user_id.jid.to_s
      log("new user req - #{user_id}")
    
      # Add a user only if they are in the DB
      add_user(user_id) if(User.find_by_login(user_id))
    end
  
    @jabber.subscription_requests do |user_id, presence|
      log("sub request from #{user_id}: #{presence}")
    
      # Add a user only if they are in the DB
      add_user(user_id) if(User.find_by_login(user_id))
    end 
  
    @jabber.presence_updates do |user_id, new_presence|
      log("presence update #{user_id} - #{new_presence}")

      from_user = User.find_by_login(user_id)
      remove_user(user_id) unless from_user

      if from_user and from_user.status != 'no_messages'
         old_presence = from_user.status
         from_user.update_attribute(:status, new_presence)

         log("presence update success #{user_id} - #{new_presence}")
       
         if(old_presence == 'unavailable' and can_send_message?(new_presence))
           users = online_users.collect {|u| u.nick || u.login }
           send_message(user_id, "Hello komrade, I am currently monitoring: #{users.join(", ")}")
           send_message(user_id, "History at #{BASE_URL}/messages or /h")
           send_message(user_id, "Last 10 messages")
           messge += Messages.history(10).collect {|m| m.to_s }.join("\n")
           send_message(user_id, message)
         end
      end
    end  
  
    sleep 2
  rescue StandardError => e
    log("bot error - #{e.message}\n#{e.backtrace.join("\n")}")
  end
end
