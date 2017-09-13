
class Template{
    
	public var name(default, null):String;
	public var text:String;
	public var parameters:Array<String>;
	public var NumParams(get, null):Int;
	function get_NumParams():Int{return parameters.length;}

	public function new(taskName:String, text:String, params:Array<String>){
		name = taskName;
		this.text = text;
		parameters = new Array<String>();
		if(params != null && params.length > 0){
			for(p in params){
				if(parameters.indexOf(p) == -1)
					parameters.push(p);
			}
		}
	}

	public function call(inputParams:Array<String>):String{
		if(inputParams == null || parameters.length != inputParams.length) { trace('called: ${name} parameters incorrect!'); return "";}
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