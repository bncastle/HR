
class Template{
    
	public var name(default, null):String;
	public var text:String;
	public var parameters:Array<String>;
	public var NumParams(get, null):Int;
	function get_NumParams():Int{return parameters.length;}

	public function new(templateName:String, text:String, params:Array<String>){
		name = templateName;
		this.text = text;
		parameters = [];
		if(params != null){
			for(p in params){
				if(parameters.indexOf(p) == -1)
					parameters.push(p);
			}
		}
	}

	public function check_parameters(inputParams:Array<String>):Bool{
		if(inputParams == null || parameters.length != inputParams.length) { 
			Sys.println('Template error: ${name} requires ${parameters.length} parameters but was only passed ${inputParams.length}!'); 
			return false;
		}
		return true;
	}

	public function call(inputParams:Array<String>):String{
		if(!check_parameters(inputParams)) return "";

		var newString:String = this.text;
		//Parameters are specified in order
		// static var varRegex:EReg = ~/@([A-Za-z0-9_]+)/gi;
		for(i in 0...parameters.length ){
			var search:EReg = new EReg('\\$(${parameters[i]})','gi');
			newString = search.replace(newString, inputParams[i]);
		}
		return newString;
	}

	public function toString():String{
		var sb:StringBuf = new StringBuf();
		sb.add('Name: $name\n');
		sb.add('Parameters: ');
		
		for	(p in parameters){
			sb.add(p);
			sb.add(' ');
		}

		sb.add('Text: ');
		sb.add(text);

		return sb.toString();
	}
}