class Message < ActiveRecord::Base
  belongs_to :user
  
  def self.history(param)
    # is the param a date, a date range, a number or a
    conditions = case param.to_s 
      when /\d+/
        {:limit => $1}
      when /(\d+)\.\.\.?(\d+)/
        {:limit => "{$1},{$2.to_i - $1.to_i}"}
      else
        {:limit => 20}
    end
    Message.find(:all, conditions.merge({:order => "created_at DESC"}))
  end
  
  def to_s
    "*#{self.created_at.strftime("%a %H:%M")} #{self.nick || self.im_userid}:* #{self.body}"
  end
end
