module GraphicsSlice
    
  # @return <Hash> Lookup of storage location names and absolute paths
  def self.storage_locations
    @storage_locations ||= self[:storage_locations] || {}
  end
  
  # Generate an image by triggering a textim GET request
  #
  # @return <Merb::Controller> The controller that processed the request.
  def self.generate_textim(string, options = {}, &block)
    url, query_param = url_for_textim(string, options.merge(:return_qp => true))        
    rack = Rack::MockRequest.new(Merb::Rack::Application.new)
    rack.get(url, (options[:params] || {}).merge(:t => query_param), options[:env] || {}, &block)
  end
  
  # Return an encoded url for use with textim - takes :path_prefix into account
  #
  # @return <String> The encoded url.
  def self.url_for_textim(string, options = {})
    defaults = { :preset => :default, :format => 'png', :append_qp => true }
    options.replace(defaults.merge(options))
    options[:base] ||= self[:path_prefix].blank? ? "/textim" : "/#{self[:path_prefix]}/textim"
    
    string   = Iconv::conv('iso-8859-1', 'utf-8', string)
    checksum = Digest::MD5.hexdigest([string, options[:preset], options[:format]].compact.join)
    prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
    filename = prefix + ".#{options[:format]}"
    return [filename, hexencode(string)] if options[:return_qp]
    options[:append_qp] ? filename + "?t=#{hexencode(string)}" : filename
  end
  
  # Generate an image by triggering an image GET request
  #
  # @return <Merb::Controller> The controller that processed the request.
  def self.generate_image(path, options = {}, &block)
    url = url_for_image(path, options)
    rack = Rack::MockRequest.new(Merb::Rack::Application.new)
    rack.get(url, options[:params] || {}, options[:env] || {}, &block)
  end
  
  # Return an encoded url for use with images - takes :path_prefix into account
  #
  # @param path<String> A relative path, from :storage location.
  #
  # @return <String> The encoded url.
  def self.url_for_image(path, options = {})
    options[:storage] ||= 'default'
    if storage_path = storage_locations[options[:storage]]
      
      if options[:absolute]
        absolute_path = path
        path = absolute_path.relative_path_from(storage_path)
      else
        absolute_path = File.expand_path(storage_path / path)
      end
     
      defaults = { :preset => :default, :format => 'jpg' }
      options.replace(defaults.merge(options))
      options[:qp]   ||= { :doc_id => options.delete(:doc_id) } if options[:doc_id]
      options[:base] ||= self[:path_prefix].blank? ? "/images" : "/#{self[:path_prefix]}/images"

      checksum = Digest::MD5.hexdigest([absolute_path, options[:preset], options[:format], self[:secret]].compact.join)
      prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
      dirname  = File.dirname(path)
      filename = File.join(*[dirname == '.' ? nil : dirname, File.basename(path, '.*') + ".#{options[:format]}"].compact)
      
      url = prefix / "#{hexencode(options[:storage]).reverse}" / "#{hexencode(File.extname(path)).reverse}" / filename
      url += "?#{options[:qp].to_params}" if options[:qp].is_a?(Hash)
      return url
    end
    return self[:default_image]
  end
  
  # Return an encoded url for use with remote images - takes :path_prefix into account
  # 
  # @param uri<String> A relative url on the remote server (see :storage for server).
  #
  # @return <String> The encoded url.
  def self.url_for_external_image(uri, options = {})
    options[:storage] ||= 'external'
    if (storage_uri = storage_locations[options[:storage]])
      absolute_uri  = storage_uri / uri
      
      defaults = { :preset => :default, :format => 'jpg' }
      options.replace(defaults.merge(options))
      options[:qp]   ||= { :doc_id => options.delete(:doc_id) } if options[:doc_id]
      options[:base] ||= self[:path_prefix].blank? ? "/external" : "/#{self[:path_prefix]}/external"
      
      checksum = Digest::MD5.hexdigest([absolute_uri, options[:preset], options[:format], self[:secret]].compact.join)
      prefix   = ([options[:base], options[:preset]] + checksum.scan(/......../).map { |part| part.reverse }.reverse).join('/')
      filename = File.join(*[File.dirname(uri), File.basename(uri, '.*') + ".#{options[:format]}"].compact)
      
      url = prefix / "#{hexencode(options[:storage]).reverse}" / "#{hexencode(File.extname(uri)).reverse}" / filename
      url += "?#{options[:qp].to_params}" if options[:qp].is_a?(Hash)
      return url
    end
    return self[:default_image]
  end
  
  # Hex encode
  def self.hexencode(string)
    string.to_s.unpack('H*').to_s
  end

  # Hex decode
  def self.hexdecode(string)
    [string.to_s].pack('H*')
  end 
  
end