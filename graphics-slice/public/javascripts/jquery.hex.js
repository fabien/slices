jQuery.hex = {
	
	_digitArray: new Array('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'),
	
  encode: function(str) { 
		var result = '';
    for (var i = 0; i < str.length; i++) { result += this._pad(this._toHex(str.charCodeAt(i)&0xff), 2, '0'); }
    return result;
	},
	
	md5: function(str) {
		return hex_md5(str);
	},
	
	_pad: function(str, len, pad) {
		var result = str; 
		for (var i = str.length; i < len; i++) { result = pad + result; }; 
		return result;
	},
	
  _toHex: function(n) {
		var result = ''; var start = true;
    for (var i=32; i>0;) { i -= 4; var digit = (n>>i) & 0xf; if (!start || digit != 0) { start = false; result += this._digitArray[digit]; } }
    return (result == '' ? '0' : result);
	}
	
};