module GraphicsSlice
  
  class Slice < Merb::Controller
    
    include GraphicsSlice::ControllerMixin
  
    controller_for_slice
    
    layout false
    
    before :authenticate, :exclude => slice[:exclude_actions] || [:show]
    before :normalize_params, :only => [:show, :delete]
    
    # Common actions to delete graphics at their cached uri location
    
    # Delete an image
    def delete(preset, format)
      only_provides(*graphics_mime_types)
      raise NotFound unless content_type && preset_exists?(preset)
      if full_request_path.index(preset_request_path) == 0 && File.exists?(full_request_path)
        success = FileUtils.rm(full_request_path) rescue nil
        cleanup_empty_dirs!(preset_request_path) if success
      end
      raise NoContent
    end
    
    # Delete all images for a preset
    def delete_preset_items(preset)
      only_provides(*graphics_mime_types)
      raise NotFound unless preset_exists?(preset)
      files = Dir.glob(preset_request_path / "**" / "*.{#{graphics_mime_types.join(',')}}")
      success = files.all? { |file| FileUtils.rm(file) rescue nil }
      cleanup_empty_dirs!(preset_request_path) if success
      raise NoContent
    end
    
    # Delete all images
    def delete_all_items
      only_provides(*graphics_mime_types)
      files = Dir.glob(base_request_path / "**" / "*.{#{graphics_mime_types.join(',')}}")
      success = files.all? { |file| FileUtils.rm(file) rescue nil }
      cleanup_empty_dirs!(base_request_path) if success
      raise NoContent
    end
    
    protected
    
    # Stub method to implement in your application
    def authenticate
      Merb.logger.info!("No authentication has been setup for GraphicsSlice")
    end
    
    def normalize_params
    end
    
  end
  
  class Images < Slice
    
    # Show a sample of all known presets
    def index
      only_provides :html
      preset_names.inject([]) do |coll, preset|
        coll << %Q[<img src="#{url_for_image(Merb.dir_for(:public) / slice[:default_image], :preset => preset, :format => 'png')}" />]
      end.join('<br />')
    end
    
    # Render a preset - pass :doc_id to enable referencing in SofaCache
    def show(preset, source_path, format)
      only_provides(*graphics_mime_types)
      raise NotFound unless source_path && preset_exists?(preset)
      img = ImMagick::Image.file(source_path)
      render_preset(preset, img)
      if image_path = save_file(img)
        store_cache_reference!(params[:doc_id], GraphicsSlice[:expire_cache] || 0) if respond_to?(:store_cache_reference!) && params[:doc_id]
        send_file(image_path, :disposition => 'inline', :type => content_type_for(format))
      else
        raise NotFound
      end
    end
        
    protected
    
    # A preset method needs to have a _preset postfix in its name and
    # recieves a ImMagick::Image instance to work with.
    def default_preset(img)
      img.crop_resized(128, 128, params[:gravity]).quality(75)
    end
    
    private
    
    def normalize_params
      params[:source_path] = nil
      params[:gravity]     = 'center' unless params[:gravity].in?('center', 'northwest', 'north', 'northeast', 'west', 'center', 'east', 'southwest', 'south', 'southeast')
      if params[:preset] && params[:format] && params[:storage] && params[:filename] && params[:original_ext]
        params[:storage]      = self.class.hexdecode(params[:storage].reverse)
        params[:original_ext] = self.class.hexdecode(params[:original_ext].reverse)
        storage_path = self.class.storage_locations[params[:storage]] 
        if storage_path && File.file?(file_path = storage_path / "#{params[:filename]}#{params[:original_ext]}") && 
          request.path == url_for_image(file_path, :storage => params[:storage], :preset => params[:preset], :format => params[:format])
          params[:source_path] = file_path 
        end
      end
    end
    
    # The absolute path derived from the request where files will be stored
    def base_request_path
      Merb.dir_for(:public) / slice_url(:graphics_slice_images_delete_all)
    end
    
  end
  
  class External < Images
        
    # Render a preset - pass :doc_id to enable referencing in SofaCache
    def show(preset, source_uri, format)
      only_provides(*graphics_mime_types)
      raise NotFound unless source_uri && preset_exists?(preset)
      self.status, headers["Location"] = 301, request.uri
      raise Created if File.exists?(full_request_path)
      store_cache_reference!(params[:doc_id], GraphicsSlice[:expire_cache] || 0) if respond_to?(:store_cache_reference!) && params[:doc_id]
      render_then_call('OK') do
        write_to_temp(RestClient.get(source_uri)) do |path|
          img = ImMagick::Image.file(path)
          render_preset(preset, img)
          save_file(img)
        end
      end
    rescue
      raise NotFound
    end
    
    private
    
    def normalize_params
      params[:source_uri] = nil
      params[:gravity]    = 'center' unless params[:gravity].in?('center', 'northwest', 'north', 'northeast', 'west', 'center', 'east', 'southwest', 'south', 'southeast')
      if params[:preset] && params[:format] && params[:storage] && params[:filename] && params[:original_ext]
        params[:storage]      = self.class.hexdecode(params[:storage].reverse)
        params[:original_ext] = self.class.hexdecode(params[:original_ext].reverse)
        if storage_uri = self.class.storage_locations[params[:storage]]
          file_uri = storage_uri / "#{params[:filename]}#{params[:original_ext]}"      
          request.path == url_for_external_image(file_uri, :storage => params[:storage], :preset => params[:preset], :format => params[:format])
          params[:source_uri] = file_uri
        end
      end
    end
    
    def write_to_temp(data, prefix = 'graphics-slice', &block)
      tmp = Tempfile.open(prefix)
      tmp.write(data)
      tmp.close
      result = yield(tmp.path) if block_given?
      tmp.unlink
      result
    end
    
    # The absolute path derived from the request where files will be stored
    def base_request_path
      Merb.dir_for(:public) / slice_url(:graphics_slice_external_delete_all)
    end
    
  end
  
  class Textim < Slice
    
    # Show a sample of all known presets
    def index
      only_provides :html
      preset_names.inject([]) do |coll, preset|
        coll << %Q[<img src="#{url_for_textim(preset, :preset => preset)}" />]
      end.join('<br />')
    end
    
    # Render a preset - pass :doc_id to enable referencing in SofaCache
    def show(preset, character_data, format)
      only_provides(*graphics_mime_types)
      raise NotFound unless content_type && preset_exists?(preset)
      runner = send(:"#{rubify(preset)}_preset", character_data) 
      raise InternalServerError unless runner.is_a?(ImMagick::Command::Runner)
      image_path = save_file(runner).filename
      store_cache_reference!(params[:doc_id], GraphicsSlice[:expire_cache] || 0) if respond_to?(:store_cache_reference!) && params[:doc_id]
      send_file(image_path, :disposition => 'inline', :type => content_type_for(format))
    end
    
    protected

    # Default preset
    # 
    # A preset method needs to have a _preset postfix in its name and
    # should return a ImMagick::Command::Runner instance.
    def default_preset(string)
      generate_label(string, :pointsize => 18, :alpha => true)
    end
    
    # Sample inverse preset
    def inverse_preset(string)
      generate_inverse_label(string, :pointsize => 18, :background => 'black', :alpha => true)
    end
    
    private
    
    # Helper to generate auto-sizing text labels
    def generate_label(string, options = {})
      merge_label_options!(options)
      
      text_image = ImMagick::convert.autosize.background(:background).gravity(:gravity)
      text_image.font(:font).pointsize(:pointsize).fill(:fill).label(:label).bordercolor(:background).border(:padding)
      final_image = text_image.instance.gravity(:gravity).extent(:extent)

      final_image.transparent(:background) if options[:alpha] && content_type == :gif
      options[:background] = :transparent  if options[:alpha] && content_type == :png

      info = text_image.run(options.merge(:label => string)).info
      options[:height] = info[:height] if options[:height] == :auto
      extent = "#{info[:width]}x#{options[:height]}"
      final_image.quiet.run(options.merge(:label => string, :autosize => info[:dimensions], :extent => extent))
    end
    
    # Helper to generate auto-sizing text labels with transparent characters on a filled background
    def generate_inverse_label(string, options = {})
      merge_label_options!(options)

      text_image = ImMagick::convert.autosize.background('white').gravity(:gravity)
      text_image.font(:font).pointsize(:pointsize).fill('black').label(:label)
      text_image.bordercolor('white').border(:padding)

      final_image = text_image.instance.gravity(:gravity).extent(:extent)
      final_image.sequence { |layer| layer.size(:autosize).canvas(:background).background(:background).extent(:extent) }
      final_image.swap('0,1').alpha(:Off).compose(:Copy_Opacity).composite
      final_image.bordercolor(:transparent).border(:bordersize) if options[:bordersize] > 0

      info = text_image.run(options.merge(:label => string)).info
      options[:height] = info[:height] if options[:height] == :auto
      extent = "#{info[:width]}x#{options[:height]}"
      final_image.quiet.run(options.merge(:label => string, :autosize => info[:dimensions], :extent => extent))
    end
    
    # Reverse-merge with default label options
    def merge_label_options!(options)
      defaults = { :background => :white, :fill => :black, :gravity => :center, :pointsize => 12, :bordersize => 0, :padding => '0x0' }
      options.replace(defaults.merge(options))
      options[:font]     = locate_font(options[:font]) if options[:font] && options[:font][0..1] != '/'
      options[:font]   ||= locate_font # locate default font
    end
    
    def normalize_params
      params[:character_data] = request_character_data
    end
    
    # The absolute path derived from the request where files will be stored
    def base_request_path
      Merb.dir_for(:public) / slice_url(:graphics_slice_textim_delete_all)
    end
    
  end
  
end