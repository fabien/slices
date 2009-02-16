module GraphicsSlice
  
  module MerbControllerMixin
    
    # Helper methods to use in your controllers
    
    def generate_image(path, options = {}, &block)
      GraphicsSlice::Slice.url_for_image(path, options, &block)
    end
    
    def url_for_image(path, options = {})
      GraphicsSlice::Slice.url_for_image(path, options)
    end
    
    def url_for_external_image(uri, options = {})
      GraphicsSlice::Slice.url_for_external_image(uri, options)
    end
    
    def generate_textim(string, options = {}, &block)
      GraphicsSlice::Slice.generate_textim(string, options, &block)
    end
    
    def url_for_textim(string, options = {})
      GraphicsSlice::Slice.url_for_textim(string, options)
    end
    
  end
  
  module ControllerMixin
    
    def self.included(base)
      base.send(:extend, ClassMethods)
    end
  
    private
    
    # Locate a font or fallback to default inside the slice distribution
    def locate_font(filename = 'union.ttf')
      font_path = slice[:font_paths].reverse.find { |path| File.file?(path / filename) }
      font_path ? font_path / filename : slice.dir_for(:stub) / 'fonts' / 'union.ttf'
    end
    
    # Get character data from params
    def request_character_data
      string = (params.key?(:t) ? params[:t] : params.find { |k,v| v.blank? }.join)
      self.class.extract_character_data(string, :preset => params[:preset], :filename => params[:filename], :format => params[:format])
    rescue
      ''
    end
    
    # Return all preset methods
    def preset_methods
      self.class.preset_methods
    end
    
    # Return all preset names
    def preset_names
      self.class.preset_names
    end
    
    # Render a preset
    def render_preset(preset, *args, &block)
      raise Merb::ControllerExceptions::NotFound unless content_type && preset_exists?(preset)
      send(:"#{rubify(preset)}_preset", *args, &block)
    end

    # Figure out if a preset handler exists
    def preset_exists?(preset)
      self.respond_to?(:"#{rubify(preset)}_preset")
    end
    
    # Check whether the checksum matches
    def valid_checksum?(absolute_path_or_uri, checksum, options = {})
      self.class.valid_checksum?(absolute_path_or_uri, checksum, options)
    end
    
    # Stores the given file (responding to save) at the current request path
    def save_file(file)
      FileUtils.mkdir_p(File.dirname(full_request_path))
      file.save(full_request_path)
    end
  
    # The absolute path derived from the request where files will be stored
    def base_request_path
      Merb.dir_for(:public) / (self.slice[:path_prefix].blank? ? "/#{action_name}" : "/#{self.slice[:path_prefix]}/#{action_name}")
    end
    
    # The absolute path for the request - the file location
    def full_request_path
      File.expand_path(Merb.dir_for(:public) / request.path)
    end

    # The absolute path to the directory of the requested preset
    def preset_request_path
      raise Merb::ControllerExceptions::NotFound unless params.key?(:preset)
      File.expand_path(base_request_path / params[:preset])
    end

    # Force-clean any empty directories within the given path (excluding itself)
    def cleanup_empty_dirs!(path)
      if File.directory?(path) && path.index(Merb.root) == 0
        system("find #{path} -depth -empty -type d -exec rmdir {} \\;")
      end
    end
    
    # A list of mimetype symbols that are considered as valid graphic formats
    def graphics_mime_types
      slice[:mime_types].keys
    end

    # Return the mime-type for the current request format
    def content_type_for(key)
      raise ArgumentError, ":#{key} is not a valid MIME-type" unless Merb::ResponderMixin::TYPES.key?(key.to_sym)
      Array(Merb::ResponderMixin::TYPES[key.to_sym][:accepts]).first
    end
    
    # Transform a string into a valid ruby method name
    def rubify(str)
      str.to_s.downcase.gsub(/\W/, ' ').strip.gsub(/(\s|-)+/, '_')
    end
    
    # Write to a Tempfile and work with the contents within the block.
    def write_to_temp(data, prefix = 'graphics-slice', &block)
      tmp = Tempfile.open(prefix)
      tmp.write(data)
      tmp.close
      result = yield(tmp.path) if block_given?
      tmp.unlink
      result
    end

    module ClassMethods
      
      def self.extended(base)
        base.class_inheritable_accessor :_storage_locations
      end
      
      # @return <Hash> Lookup of storage location paths and absolute paths
      def storage_locations
        self._storage_locations = slice[:storage_locations] || {} unless _storage_locations
        self._storage_locations
      end
      
      # Generate an image by triggering an image GET request
      #
      # @return <Merb::Controller> The controller that processed the request.
      def generate_image(path, options = {}, &block)
        url = url_for_image(path, options)
        rack = Rack::MockRequest.new(Merb::Rack::Application.new)
        rack.get(url, options[:params] || {}, options[:env] || {}, &block)
      end
      
      # Return an encoded url for use with images - takes :path_prefix into account
      #
      # @param path<String> A relative path, from :storage location.
      #
      # @return <String> The encoded url.
      def url_for_image(path, options = {})
        options[:storage] ||= 'default'
        if storage_path = storage_locations[options[:storage]]
          absolute_path = File.expand_path(storage_path / path)
         
          defaults = { :preset => :default, :format => 'jpg' }
          options.replace(defaults.merge(options))
          options[:qp]   ||= { :doc_id => options.delete(:doc_id) } if options[:doc_id]
          options[:base] ||= self.slice[:path_prefix].blank? ? "/images" : "/#{self.slice[:path_prefix]}/images"

          checksum = Digest::MD5.hexdigest([absolute_path, options[:preset], options[:format], slice[:secret]].compact.join)
          prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
          filename = File.join(*[File.dirname(path), File.basename(path, '.*') + ".#{options[:format]}"].compact)
          
          url = prefix / "#{hexencode(options[:storage]).reverse}" / "#{hexencode(File.extname(path)).reverse}" / filename
          url += "?#{options[:qp].to_params}" if options[:qp].is_a?(Hash)
          return url
        end
        return slice[:default_image]
      end
      
      # Return an encoded url for use with remote images - takes :path_prefix into account
      # 
      # @param uri<String> A relative url on the remote server (see :storage for server).
      #
      # @return <String> The encoded url.
      def url_for_external_image(uri, options = {})
        options[:storage] ||= 'external'
        if (storage_uri = storage_locations[options[:storage]])
          absolute_uri  = storage_uri / uri
          
          defaults = { :preset => :default, :format => 'jpg' }
          options.replace(defaults.merge(options))
          options[:qp]   ||= { :doc_id => options.delete(:doc_id) } if options[:doc_id]
          options[:base] ||= self.slice[:path_prefix].blank? ? "/external" : "/#{self.slice[:path_prefix]}/external"
          
          checksum = Digest::MD5.hexdigest([absolute_uri, options[:preset], options[:format], slice[:secret]].compact.join)
          prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
          filename = File.join(*[File.dirname(uri), File.basename(uri, '.*') + ".#{options[:format]}"].compact)
          
          url = prefix / "#{hexencode(options[:storage]).reverse}" / "#{hexencode(File.extname(uri)).reverse}" / filename
          url += "?#{options[:qp].to_params}" if options[:qp].is_a?(Hash)
          return url
        end
        return slice[:default_image]
      end
      
      # Ensure checksum match for path or uri.
      def valid_checksum?(absolute_path_or_uri, checksum, options = {})
        computed_checksum   = Digest::MD5.hexdigest([absolute_path_or_uri, options[:preset], options[:format], slice[:secret]].compact.join)
        normalised_checksum = checksum.split('/').reverse.map { |s| s.reverse }.join
        normalised_checksum == computed_checksum
      end
      
      # Generate an image by triggering a textim GET request
      #
      # @return <Merb::Controller> The controller that processed the request.
      def generate_textim(string, options = {}, &block)
        url, query_param = url_for_textim(string, options.merge(:return_qp => true))        
        rack = Rack::MockRequest.new(Merb::Rack::Application.new)
        rack.get(url, (options[:params] || {}).merge(:t => query_param), options[:env] || {}, &block)
      end

      # Return an encoded url for use with textim - takes :path_prefix into account
      #
      # @return <String> The encoded url.
      def url_for_textim(string, options = {})
        defaults = { :preset => :default, :format => 'png', :append_qp => true }
        options.replace(defaults.merge(options))
        options[:base] ||= self.slice[:path_prefix].blank? ? "/textim" : "/#{self.slice[:path_prefix]}/textim"
        
        string   = Iconv::conv('iso-8859-1', 'utf-8', string)
        checksum = Digest::MD5.hexdigest([string, options[:preset], options[:format]].compact.join)
        prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
        filename = prefix + ".#{options[:format]}"
        return [filename, hexencode(string)] if options[:return_qp]
        options[:append_qp] ? filename + "?t=#{hexencode(string)}" : filename
      end

      # Extract textim formatted data from the incoming url params
      def extract_character_data_from_url(url, options = {})
        if matches = url.match(/\/([^\/]+)\/([a-f0-9]{8})\/([a-f0-9]{8})\/([a-f0-9]{8})\/([a-f0-9]{8})\.(\w+)\?t=([a-f0-9]+)$/)
          options[:preset]   = matches.captures.first.to_sym
          options[:filename] = matches.captures[1..4].join('/')
          options[:format]   = matches.captures[5]
          extract_character_data(matches.captures[6], options)
        end
      end
      
      # Decodes character data from a string - validates against checksum
      def extract_character_data(string, options = {})
        defaults = { :preset => :default, :format => 'gif' }
        options.replace(defaults.merge(options))
        
        string = [string].pack('H*')
        raise 'invalid character data' unless string.length <= 256
        if options.key?(:checksum) || options.key?(:filename) # if a filename is given, use this for a checksum match
          raise 'checksum mismatch' unless Digest::MD5.hexdigest([string, options[:preset], options[:format]].compact.join) == options[:checksum] || options[:filename].split('/').reverse.map { |s| s.reverse }.join
        end
        Iconv::conv('utf-8', 'iso-8859-1', string)
      end
      
      # Return all preset methods
      def preset_methods
        instance_methods.grep(/_preset$/)
      end
      
      # Return all preset names
      def preset_names
        preset_methods.map { |m| m[/^(.*?)_preset$/, 1] }.sort
      end
      
      # Hex encode
      def hexencode(string)
        string.to_s.unpack('H*').to_s
      end

      # Hex decode
      def hexdecode(string)
        [string.to_s].pack('H*')
      end
      
      private
      
      # Make sure no *_preset methods are callable actions
      def _callable_methods
        super - preset_methods
      end
      
    end
   
  end
end