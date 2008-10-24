require 'interfaces/twitter'
require 'interfaces/xmpp'

class InterfaceMaster
  class <<self
    include Spawn
  
    def run_all
      for interface_class in [TwitterInterface, XmppInterface]
        spawn do
          instance = interface_class.new
          instance.run
        end
      end
    
    end
  end
end