class MessagesController < ApplicationController
  def index
    @history = Message.history(params[:id] || 200)
    @users = User.find(:all)
    
    render :action => :history
  end
end
