import sys.FileSystem;
import sys.io.File;
using StringTools;

class HrTokenizer{
    
	static var WHITESPACE:Array<Int> = ["\t".code, " ".code, "\r".code];
	static var LINE_BREAKS:Array<Int> = ["\n".code, "\r".code];
	static var KEYWORDS:Map<String,HRToken> = [ "variables" => HRToken.variableSection, "tasks" => HRToken.taskSection, "templates" => HRToken.templateSection, "use" => HRToken.useSection];

	var content:String;
	var tokens:Array<Token>;
	var index:Int;
	var start:Int;
	//The current line of text we're processing
	var line:Int;
	//The column where the parser is currently
	var col:Int;
	//If > 0 then the tokenizer thinks its inside an array
	var arrayLevel:Int;

	//If this is true, then there were errors processing the file or text input
	public var wasError(default, null):Bool;
	//Gets the previous token type if there was one
	var prevTokenType(get,null):HRToken;
	function get_prevTokenType():HRToken { return tokens.length - 1 >= 0 ? tokens[tokens.length - 1].type : HRToken.none;}

	//Gets the current lexeme length
	var lexemeLength(get,null):Int;
	function get_lexemeLength():Int { return (index - start) > 0 ? (index - start) : 0;}

	//Gets the current lexeme
	var lexeme(get,null):String;
	function get_lexeme():String {
		if(start > index || start == index) return "";
		else return content.substring(start, index);
	}

	public function new(){
		tokens = new Array<Token>();
	}

	function Reset(){
		tokens = new Array<Token>();
		content = null;
		index = 0;
		start = 0;
		line = 1;
		col = 1;
		arrayLevel = 0;
		wasError= false;
	}

	public function parseFile(filename:String): Array<Token>{
		Reset();
		//Try to get the file contents
		if(!getFileContents(filename)){
			return null;
		}
		//Now grab the tokens from the file
		getTokens();

		return tokens;
	}

	public function parseText(text:String):Array<Token>{
		Reset();
		if(text == null || text == "") return null;
		content = text;
		getTokens();
		return tokens;
	}

	function getFileContents(filename:String):Bool {
		if(!FileSystem.exists(filename)){
			Sys.println('File ${filename} not found!');
			return false;
		}

		try{
			content = File.getContent(filename);
		}
		catch(ex:Dynamic){
			Sys.println("Error: ${ex}");
		}

		return true;
	}

	//Use this function to log errors in this class
	//this allows us to redirect our errors easily
	function logError(err:Dynamic, ?tk:Token = null){
		if(tk != null)
			Sys.println('Error [${tk.line}:${tk.column}] ${err}');
		else
			Sys.println('Error [${line}:${col - lexemeLength}] ${err}');
		wasError = true;
	}

	function addToken(t:HRToken){
		// trace('Add ${t} |${lexeme}|');
		tokens.push(new Token(t, line, col - lexemeLength, lexeme));
	}
	function removeLastToken(){
		// trace('Remove ${tokens[tokens.length - 1].type} |${tokens[tokens.length - 1].lexeme}|');
		tokens.pop();
	}

	function getTokens(){
		var useSection:Bool = false;

		while(!isEof()){
			eat(WHITESPACE);
			start = index;
			var c:Int = nextChar();

			//the double-dash must be at the very beginning
			if(c == '-'.code && peek() == '-'.code && col == 2){
				nextChar();
				addToken(HRToken.double_dash);
				useSection = false;
				continue;
			}

			switch(c){
				case '#'.code : matchUntil(LINE_BREAKS); //it's a comment
				case '['.code : arrayLevel++; addToken(HRToken.leftBracket);
				case '('.code : addToken(HRToken.leftParen);
				case ')'.code : addToken(HRToken.rightParen);
				case ']'.code : 
					arrayLevel--; 
					if(arrayLevel < 0){ //Unmatched ']'?
						logError('unmatched ]');
					}
					else if(prevTokenType == HRToken.comma){
							logError('invalid comma');
						}
					addToken(HRToken.rightBracket);
				case '='.code :
					if(prevTokenType == HRToken.variableSection || prevTokenType == HRToken.taskSection)
						logError("section headings not allowed on the left side of an ="); 
					else if(prevTokenType != HRToken.identifier  && prevTokenType != HRToken.rightParen)
						logError("Identifier expected before ="); 
					addToken(HRToken.equals);
				// case ':'.code : addToken(HRToken.colon);
				case ','.code : addToken(HRToken.comma);
				case '\n'.code : start = index; line++; col = 1; if(prevTokenType == HRToken.equals) logError("value required after equals", tokens[tokens.length -1]);
				default:
					//We expect a value after an '='
					if(prevTokenType == HRToken.equals){
						matchUntil(LINE_BREAKS);
						if(lexemeLength > 0)
							addToken(HRToken.value);
						else
							logError('Expected a value after =');
					}
					else if(arrayLevel > 0){ //Are we in an array?							
							if(c == ':'.code){ //Is this a task reference?
								start = index;
								matchIdentifier();
								if(lexemeLength > 0){
									var t = KEYWORDS.get(lexeme);
									if(t != null){
										logError("keywords are not allowed here");
									}
									else if(peek() == ':'.code) {
										//We have a variable or task output ref so it must not be a command
										matchUntil([','.code, ']'.code]);
										//Make sure to include the ':' in the token we save here. We want the whole thing
										start--;
										addToken(HRToken.value);
									}
									else{
										addToken(HRToken.identifier);
									}
								}
								else{
									logError('Expected a taskName identifier after :');
								}
							}
							//Is it a template perhaps?
							else if(c == '@'.code){
								matchUntil([')'.code, ']'.code]);
								if(lexemeLength > 0){
									match(')'.code);
									addToken(HRToken.value);
								}
								else
									logError('Expected a template call!');
							}
							else{ //otherwise, it must a full command
								matchUntil(LINE_BREAKS);
								if(lexemeLength > 0)
									addToken(HRToken.value);
								else
									logError('Expected a full command');
							}
					}
					else if (isAlpha(c) || c == '_'.code){
						if(useSection){
							matchUntil(WHITESPACE);
							addToken(HRToken.value);
							continue;
						}

						matchIdentifier();
						if(lexemeLength > 0){
							//is it a keyword?
							var t = KEYWORDS.get(lexeme);
							if(t != null){
								if(prevTokenType == HRToken.double_dash){
									//Remove the double dash as the parser does not need it
									removeLastToken();
									addToken(t);

									if(t == HRToken.useSection)
										useSection = true;
									else
										useSection = false;
								}
								else{
									logError('Is "$lexeme" a section header? If so, it must be:--$lexeme');
								}
							}
							else{ //It must be an identifier
								//Was there another identifier before this one? That isn't allowed
								if(prevTokenType == HRToken.identifier){
									logError("Expected an =, not another identifier");
								}
								else{
									if(prevTokenType == HRToken.double_dash)
										logError('Expected one of [variables, tasks, templates, use] after "--" found $lexeme');
									addToken(HRToken.identifier);
								}
							}
						}
					}
					else
						logError('Unrecognized token: ${lexeme}');	
			}
		}
	}

	function eat(chars:Array<Int>){
		while(!isEof() && chars.indexOf(peek()) > -1){
			nextChar();
			start = index;
		}
	}

	function match(char:Int):Bool{
		if(!isEof() && peek() == char) { nextChar(); return true; }
		else return false;
	}
	function matchWhile(chars:Array<Int>){
		while(!isEof() && chars.indexOf(peek()) > -1) nextChar();
	}

	function matchUntil(chars:Array<Int>){
		while(!isEof() && chars.indexOf(peek()) == -1 ) nextChar();
	}

	//If we call this function, then we already know that the first character is an alpha
	function matchIdentifier(){
		while(isAlpha(peek()) || isDigit(peek())) nextChar();
	}

	function isEof():Bool{
		return index >= content.length;
	}

	function isAlpha(ch:Int):Bool{
		return (ch >= 'a'.code && ch <= 'z'.code) || (ch >= 'A'.code && ch <= 'Z'.code) || ch == '_'.code;
	}

	function isDigit(ch:Int):Bool{
		return ch >= '0'.code && ch <= '9'.code;
	}

	function nextChar(): Int {
		index++;
		col++;
		return content.fastCodeAt(index - 1);
	}

	//peeks at the next character in the stream
	function peek():Int {
		if(isEof()) return 0;
		return content.fastCodeAt(index);
	}
}