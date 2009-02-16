if defined?(Merb::Plugins)

  require 'merb-slices'
  require 'im_magick'
  require 'iconv'
  require 'base64'
  require 'digest/md5'
  require 'uri'
  require 'rest_client'
  
  require 'graphics-slice/controller_mixin'
  
  Merb::Plugins.add_rakefiles "graphics-slice/merbtasks", "graphics-slice/slicetasks"

  # Register the Slice for the current host application
  Merb::Slices::register(__FILE__)
  
  # Slice configuration - set this in a before_app_loads callback.
  Merb::Slices::config[:graphics_slice] = { 
    :mime_types        => { :jpg => ['image/jpeg'], :png => ['image/png'], :gif => ['image/gif'] },
    :secret            => 'graphicsecret',
    :username          => 'admin',
    :password          => 'secret',
    :exclude_actions   => [:show],
    :expire_cache      => (3600 * 24),
    :default_image     => 'fallback.jpg',
    :default_storage   => 'graphics-slice',
    :storage_locations => { 
      'default'        => Merb.dir_for(:image),
      'graphics-slice' => Merb.dir_for(:public) / 'slices/graphics-slice/images',
      'flickr'         => 'http://static.flickr.com'
    }
  }
  
  # Be sure to set the correct base path for jquery.textim.js using:
  #
  # $.fn.textim.defaults.base = '/graphics-slice/textim';
  
  # All Slice code is expected to be namespaced inside a module
  module GraphicsSlice
    
    # Slice metadata
    self.description = "GraphicsSlice adds graphics handling capabilities to Merb."
    self.version = "0.9.5"
    self.author = "Fabien Franzen"
    
    # Stub classes loaded hook - runs before LoadClasses BootLoader
    # right after a slice's classes have been loaded internally.
    def self.loaded
      Merb::Controller.send(:include, GraphicsSlice::MerbControllerMixin)
    end
    
    # Initialization hook - runs before AfterAppLoads BootLoader
    #
    # Use after_app_loads to append font paths - will be searched in reverse.
    def self.init
      config[:mime_types].each { |ext, mime| Merb::add_mime_type(ext, nil, mime) }
      config[:font_paths] = [dir_for(:stub) / 'fonts', app_dir_for(:root) / 'fonts']
    end
    
    # Activation hook - runs after AfterAppLoads BootLoader
    def self.activate
    end
    
    # Deactivation hook - triggered by Merb::Slices.deactivate(GraphicsSlice)
    def self.deactivate
    end
    
    # Setup routes inside the host application
    #
    # @param scope<Merb::Router::Behaviour>
    #  Routes will be added within this scope (namespace). In fact, any 
    #  router behaviour is a valid namespace, so you can attach
    #  routes at any level of your router setup.
    def self.setup_router(scope)
      scope.to(:controller => 'textim') do |textim|
        # generate a graphic at the request path location unless it exists
        textim.match("/textim/:preset/:filename.:format", :method => :get, 
          :filename => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/).to(:action => 'show')
        # remove the specified textim image from the request path location
        textim.match("/textim/:preset/:filename.:format", :method => :delete, 
          :filename => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/).to(:action => 'delete')
        textim.match("/textim/index.html").to(:action => 'index')
        # remove all textim images generated by a certain preset
        textim.match("/textim/:preset", :method => :delete).to(:action => 'delete_preset_items').name(:graphics_slice_textim_delete_preset)
        # remove all cached textim images
        textim.match("/textim", :method => :delete).to(:action => 'delete_all_items').name(:graphics_slice_textim_delete_all)
      end
      scope.to(:controller => 'images') do |images|
        # generate an image at the request path location unless it exists - stores asset reference
        images.match("/images/:preset/:checksum/:storage/:original_ext/:filename.:format", :method => :get, 
          :checksum => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/, :storage => /[a-f0-9]+/, :original_ext => /[a-f0-9]+/, :filename => /[^\.]+/).to(:action => 'show')
        # remove the specified image from the request path location - using the previously stored asset reference       
        images.match("/images/:preset/:checksum/:storage/:original_ext/:filename.:format", :method => :delete, 
          :checksum => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/, :storage => /[a-f0-9]+/, :original_ext => /[a-f0-9]+/, :filename => /[^\.]+/).to(:action => 'delete')
        images.match("/images/index.html").to(:action => 'index')     
        # remove all textim images generated by a certain preset
        images.match("/images/:preset", :method => :delete).to(:action => 'delete_preset_items').name(:graphics_slice_images_delete_preset)
        # remove all images generated by a certain preset - using asset references in the preset context
        images.match("/images", :method => :delete).to(:action => 'delete_all_items').name(:graphics_slice_images_delete_all)
      end
      scope.to(:controller => 'external') do |images|
        # generate an image at the request path location unless it exists - stores asset reference
        images.match("/external/:preset/:checksum/:storage/:original_ext/:filename.:format", :method => :get, 
          :checksum => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/, :storage => /[a-f0-9]+/, :original_ext => /[a-f0-9]+/, :filename => /[^\.]+/).to(:action => 'show')
        # remove the specified image from the request path location - using the previously stored asset reference       
        images.match("/external/:preset/:checksum/:storage/:original_ext/:filename.:format", :method => :delete, 
          :checksum => /[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}\/[a-f0-9]{8}/, :storage => /[a-f0-9]+/, :original_ext => /[a-f0-9]+/, :filename => /[^\.]+/).to(:action => 'delete')
        images.match("/external/index.html").to(:action => 'index')       
        # remove all textim images generated by a certain preset
        images.match("/external/:preset", :method => :delete).to(:action => 'delete_preset_items').name(:graphics_slice_external_delete_preset)
        # remove all images generated by a certain preset - using asset references in the preset context
        images.match("/external", :method => :delete).to(:action => 'delete_all_items').name(:graphics_slice_external_delete_all)
      end
    end
    
    # This sets up a very thin slice's structure.
    def self.setup_default_structure!
      self.push_app_path(:root, Merb.root / 'slices' / self.identifier, nil)
      
      self.push_path(:stub, root_path('stubs'), nil)
      self.push_app_path(:stub, app_dir_for(:root), nil)
      
      self.push_path(:application, root, 'slice.rb')
      self.push_app_path(:application, app_dir_for(:root), 'slice.rb')
            
      self.push_path(:public, root_path('public'), nil)
      self.push_app_path(:public, Merb.root / 'public' / 'slices' / self.identifier, nil)
      
      public_components.each do |component|
        self.push_path(component, dir_for(:public) / "#{component}s", nil)
        self.push_app_path(component, app_dir_for(:public) / "#{component}s", nil)
      end
    end
    
  end
  
  # Setup the slice layout for GraphicsSlice
  #
  # Use GraphicsSlice.push_path and GraphicsSlice.push_app_path
  # to set paths to graphics-slice-level and app-level paths. Example:
  #
  # GraphicsSlice.push_path(:application, GraphicsSlice.root)
  # GraphicsSlice.push_app_path(:application, Merb.root / 'slices' / 'graphics-slice')
  # ...
  #
  # Any component path that hasn't been set will default to GraphicsSlice.root
  #
  # For a very thin slice we just add application.rb and :public locations.
  GraphicsSlice.setup_default_structure!
  
end