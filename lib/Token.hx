package lib;

class Token{
    
	public var type(default,null):HRToken;
	public var lexeme(default,null):String;
	public var line(default,null):Int;
	public var column(default,null):Int;

	public function new(t:HRToken, line:Int, col:Int, ?lex:String = null){
		type = t;
		this.line = line;
		column = col;
		lexeme = lex;
	}

	public function toString(){
		return '${type} |${line}:${column}| |${lexeme}|';
	}
}