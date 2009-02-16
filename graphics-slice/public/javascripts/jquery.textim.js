(function($) {

  $.fn.textim = function(preset, format, splitwords) {
    return this.each(function() {
  		var reference = $(this);
  		var nodes = $(this).contents();
  		var title = $(this).attr('title');
  		$(this).empty();
  		nodes.each(function() {
  			if ($(this).is('strong,em')) {
  				var text = $(this).text();
  				var name = this.nodeName.toLowerCase();
  				var elem = img(text, preset + '-' + name, format).addClass(name);
  				reference.append(' ').append(elem).append(' ');	
  			} else if ($(this).is('span[class]')) {
  				var text = $(this).text();
  				var name = $(this).attr('class');
  				var elem = img(text, preset + '-' + name, format).addClass(name);
  				reference.append(' ').append(elem).append(' ');						
  			} else if ($(this).is('br')) {
  				reference.append(this);
  			} else if ($(this).is('[nodeType=3]')) {
  				var text = this.nodeValue.replace(/^\s*|\s*$/g, '');
  				if (splitwords) {
  					var tokens = text.split(/\s+/);
  					var token_count = tokens.length;
  					for(var i = 0; i < tokens.length; i++) {
  						var token = tokens[i].replace(/^\s*|\s*$/g, '');
  						if(token != '') { reference.append(img(token, preset, format, title)); }
  						if(i < (token_count - 1)) { reference.append(' '); }
  					}
  				} else {
  					if(token != '') { reference.append(img(text, preset, format, title)); }
  				}
  			}
  		});
    });
  }
  
  $.fn.textimWithFallback = function(preset, format, splitwords, fbClassName) {
    var reference = $(this); var text = reference.text();
    return $(this).textim(preset, format, splitwords).children('img').addClass('with_fallback').end().append($.create('span', { className: fbClassName || 'fallback' }, text));
  }
  
  $.fn.textimCss = function(preset, format) {
    return this.each(function() {
      var text = $(this).html();
  		$(this).wrapInner('<span style="display:none"></span>').css({ display: 'block', background: 'url(' + uri(text, preset, format, true) + ') 0 50% no-repeat' });
    });
  }
  
  $.fn.textimSubmit = function(preset, format) {
    return this.each(function() {
      var text = $(this).val();
      var input = $.create('input', { type: 'image', src: uri(text, preset, format, true), id: $(this).attr('id'), className: $(this).attr('class') }).addClass('textim');
      $(this).replaceWith(input);
    });
  }
  
  $.fn.textim.defaults = { base: '/graphics' };
  
  function uri(text, preset, format, append_qp) {
    preset = preset || 'default'; format = format || 'gif'; var fname = []; var hsh = jQuery.hex.md5(text + preset + format);
    for(var x, i = 0, c = -1, l = hsh.length, n = []; i < l; i++) { (x = i % 8) ? n[c][x] = hsh.charAt(i) : n[++c] = [hsh.charAt(i)]; }
    for(var i = 0; i < n.length; i++) { fname[i] = n[i].reverse().join(''); }
    var img_uri = $.fn.textim.defaults.base + '/' + preset + '/' + fname.reverse().join('/') + '.' + format;
    if(append_qp) { img_uri += '?t=' + jQuery.hex.encode(text); }
    return img_uri;
  }
  
  function img(text, preset, format, title) {
    var image = $.create('img', { src: uri(text, preset, format), title: title || text, alt: text });
    $(image).load(function() { $(this).addClass('textim'); });
    $(image).error(function() { if(!$(this).data('skip')) { var new_src = uri(text, preset, format, true); if($(this).attr('src') != new_src) { $(this).data('skip', true); $(this).attr('src', new_src); } } });    
    return image;
  }
  
})(jQuery);