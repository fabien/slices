module GraphicsSlice
  
  class Slice
    
    # Stub to override to protect any action except :show
    def authenticate
      basic_authentication('GraphicsSlice') { |username, password| username == GraphicsSlice[:username] && password == GraphicsSlice[:password] }
    end
    
  end
  
  class Images
    
    # A preset method needs to have a _preset postfix in its name and
    # recieves a ImMagick::Image instance to work with.
    def sample_preset(img)
      img.crop_resized(200, 200, params[:gravity] || 'center').quality(75)
    end
    
  end 
  
  class Textim
    
    # A preset method needs to have a _preset postfix in its name and
    # should return a ImMagick::Command::Runner instance - recieves characted data.
    def sample_preset(string)
      generate_label(string, :pointsize => 18, :background => 'black', :fill => 'red', :alpha => true)
    end
    
  end
  
end