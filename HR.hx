import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
using StringTools;

// @author Bryan Castleberry
//
//The comments below are meant to utilize my Hix utility to compile/run
//without needing a build.hxml or command line options. Hix can be found here:
//https://github.com/bncastle/hix
//
//::hix -main HR --no-traces -dce full -cpp bin
//::hix:neko -main HR --no-traces -dce full -neko hr.n
//::hix:debug -main HR -cpp bin

class HR
{
	static inline var VERSION = "0.5";
	static inline var CFG_FILE = "config.hr";
	static inline var ERR_TASK_NOT_FOUND = -1025;
	static inline var ERR_CYCLIC_DEPENDENCE = -1026;
	static inline var ERR_NO_TASKS_FOUND = -1027;
 	static inline var ERR_ILLEGAL_TASK_REF= -1028;

	var verbose:Bool = false;
	var tokenizer(default,null):HrTokenizer;
	var parser:HrParser;
	var tokens:Array<Token>;
	var taskResults:Map<String,String>;
	var dependencyMap:Map<String,Array<String>>;

	static function main(): Int
	{
		log('\nHR Version $VERSION: A task runner.');
		log("Copyright 2017 Pixelbyte Studios");

		//Note this: We want the config file in the directory where we were invoked!
		var cfgFile:String = Sys.getCwd() + CFG_FILE;
		var printTasks:Bool = false;
		var retCode:Int = 0;

		if (Sys.args().length < 1)
		{
			log("===================================");
			log("Usage: HR.exe [-v] <task_taskName>");
			log("-v prints out each command as it is executed");
			// log("-t (prints a list of valid tasks)");

			if (!HR.CheckForConfigFile(cfgFile))
			{
				log('Make a $CFG_FILE file and put it in your project directory.');
				return -1;
			}
			else{
				log("");
				printTasks = true;
			}
		}

		var h = new HR();
		var taskIndex = 0;

		//Parse the config file
		if (!h.ParseConfig(cfgFile))
		{
			return -1;
		}

		//print all tasks in the file
		if (printTasks)
		{
			h.PrintAvailableTasks();
			return -1;
		}

		//1st, create a dependency map that maps ALL the tasks direct dependencies
		h.dependencyMap = h.createDependencyMap();

		//Check for any undefined tasks. These are most likely to occur
		//when there is an embedded task reference
		retCode = h.checkForUndefinedTasks();
		if(retCode != 0){
			return retCode;
		}

		//Check the config file for cyclical dependencies
		retCode = h.checkForCyclicalDependencies();
		if(retCode != 0){
			error('Cyclical dependencies found in "$CFG_FILE".');
			return retCode;
		}

		//Verbose mode?
		if (Sys.args()[0] == "-v")
		{
			h.verbose = true;
			taskIndex++;
		}

		//Get the task to execute
		var taskName:String = Sys.args()[taskIndex];

		//Does the task exist?
		if(!h.parser.tasks.exists(taskName)){
			error('"$taskName"" is not defined');
			return ERR_TASK_NOT_FOUND;
		}

		//Check for any illegal embedded task references
		//If a task refers to another in one of its commands and that task has multiple
		//results, then error out
		retCode = h.checkForIllegalEmbeddedTaskRefs(h.dependencyMap[taskName]);
		if(retCode != 0) return retCode;

		retCode = h.RunTask(taskName);
		if ( retCode != 0)
			return retCode;

		return retCode;
	}

	public function new()
	{
		//Create a new parser
		tokenizer = new HrTokenizer();
		taskResults= new Map<String,String>();
		dependencyMap= new Map<String,Array<String>>();
	}

	function ParseConfig(cfgFile:String): Bool
	{
		tokens = tokenizer.parseFile(cfgFile);
		if(tokens != null && !tokenizer.wasError){
			parser = HrParser.ParseTokens(tokens);
			
			//Print out all our tokens
			// for(t in tokens)
			// 	Sys.println('${t.type} => ${t.lexeme}');

			return (parser != null && !parser.wasError);
		}
		else return false;
	}

	static function error(msg:Dynamic){
		Sys.println('Error: $msg');
	}

	static function log(msg:Dynamic){
		Sys.println(msg);
	}

	//Gets the direct dependencies for the given task
	function getDirectDependencies(taskName:String):Array<String>
	{
		var stack:Array<String> = [];

		if(taskName == null) return null;

		var tasks = parser.tasks.get(taskName);
		if(tasks == null){
			error('unable to find commands for "$taskName"');
			return null;
		}

		//for each task in tasks look for direct dependencies
		for(i in 0 ... tasks.length){
			if(tasks[i].isTaskRef){
				stack.push(tasks[i].text);
			}
			else{ //it must be a command so get those deps
				var cmdDeps = parser.GetEmbeddedTaskReferences(tasks[i]);

				//now we need to go through these and get their deps
				if(cmdDeps != null){
					for(j in 0 ... cmdDeps.length){ //if this dep is not already on the stack, push it
						if(stack.indexOf(cmdDeps[j]) == -1){
							stack.push(cmdDeps[j]);
						}
					}
				}
			}
		}
				
		return stack;
	}

	function createDependencyMap():Map<String, Array<String>>{
		var map:Map<String, Array<String>> = new Map<String,Array<String>>();

		//Create a dependency map for each task we can then use
		//to check for cyclical deps, etc
		for(task in parser.tasks.keys()){
			var deps = getDirectDependencies(task);
			if(deps != null)
				map.set(task, deps);
		}
		return map;
	}

	//returns a non-zero code if ANY cyclical deps are found
	//this may not be the quickest way but it is easiest to just check
	//all tasks for cyclical dependencies
	function checkForCyclicalDependencies():Int{
		var retCode = 0;
		//Holds the tasks that we've already checked
		var checked:Array<String> = [];
		//Go through all dependencies of a task and see if there are any cyclical referrals
		for(taskName in dependencyMap.keys()){
			for (node in dependencyMap[taskName]){
				if(taskName == node || checked.indexOf(node) > -1) continue;
				else if(dependencyMap[node].indexOf(taskName) > -1){
					error('Cyclical dependency: $taskName <=> ${node}');
					retCode = ERR_CYCLIC_DEPENDENCE;
				}
			}
			checked.push(taskName); //We've checked this task with all others
		}
		return retCode;
	}

	//Checks all tasks to see if there is an embedded taskRef that is not defined
	function checkForUndefinedTasks():Int{
		var retCode = 0;
		for(taskName in dependencyMap.keys()){
			// trace('$taskName => ${dependencyMap[taskName]}');
			for(subTask in dependencyMap[taskName]){
				if(dependencyMap[subTask] == null){
					error('Missing "$subTask" definition from task "$taskName". Either it is a variable or a task?');
					retCode = ERR_TASK_NOT_FOUND;
					continue;
				}
			}
		}
		return retCode;
	}

	//Given a task callstack, this checks each task to see if 
	//it has any embedded tasks in a command AND that task has multiple results
	//which is illegal
	function checkForIllegalEmbeddedTaskRefs(callStack:Array<String>):Int{
		var retCode = 0;
		for(taskName in callStack){
			//  trace('Task: $taskName');
			//Get the ACTUAL tasks here
			var tasks = parser.tasks.get(taskName);
			for(cmd in tasks){
				//  trace('Command: $cmd');
				//Check for embedded refs in this task
				if(!cmd.isTaskRef){
					var cmdRefs = parser.GetEmbeddedTaskReferences(cmd);
					if(cmdRefs != null){
						for(ref in cmdRefs){ //Now check the referred task for multiple results
							//  trace('$ref');
							if(parser.tasks.get(ref).length > 1){
								error('Task "$ref" has multiple results so cannot be used as an embedded task reference in task "$taskName"');
								retCode = ERR_ILLEGAL_TASK_REF;
							}
						}
					}
				}
			}
		}
		return retCode;
	}

	function RunTask(taskName: String, ?showOutput:Bool = true):Int
	{
		var retCode = 0;
		var tasks = parser.tasks.get(taskName);

		//Now run each taskRef or command in sequence
		for(i in 0...tasks.length){		
			//See if this task is just a task reference. If it is, run it
			if(tasks[i].isTaskRef){
				retCode = RunTask(tasks[i].text);
				if(retCode != 0) return retCode;
			}
			else { //Must be a command
				//See if the command has any references to other task outputs
				//if those tasks have not been executed, then execute them
				var taskRefs = parser.GetEmbeddedTaskReferences(tasks[i]);
				if(taskRefs != null){
					for(t in taskRefs){
						if(!taskResults.exists(t)){
							retCode = RunTask(t);
							if(retCode != 0) return retCode;
						}
					}
				}

				//Expand out any task results that need to be expanded for this command
				parser.Expand(tasks[i], taskResults);

				//Run the command and if it fails, bail
				var retCode = RunCommand(taskName, tasks[i].text, showOutput);
				// trace('retCode: $retCode');
				if (retCode != 0) return retCode;
			}
		}
		return retCode;
	}

	function Contains(val:String, arr:Array<Result>):Bool{
		for(res in arr){
			if(res.text == val) return true;
		}
		return false;
	}

	function RunCommand(taskName:String, cmd:String, showOutput:Bool):Int{
		//If we are in verbose mode, print the command too
		if(verbose){}
			log('\nRun: $cmd');

		var proc = new Process(cmd);
		var output:String = proc.stdout.readAll().toString();
		var err:String = proc.stderr.readAll().toString();
		var retcode:Int = proc.exitCode();
		proc.close();

		if(output.length > 0){
			if(taskName != null){
				// trace('Set results for $taskName => |$output|');
				taskResults.set(taskName, output.rtrim());
			}
			if(showOutput)
				Sys.print(output);
		}
		 if(err.length > 0)
			Sys.print(err);

		return retcode;
	}

	function PrintAvailableTasks(){
		log("Available Tasks:");
		for	(taskName in parser.tasks.keys()){
			log(taskName);
		}
	}

	static function CheckForConfigFile(cfgFile:String): Bool{
		//Check for a valid config file
		if (!FileSystem.exists(cfgFile))
		{
			Sys.println("Config file " + cfgFile + " doesn't exist.");
			return false;
		}
		return true;
	}
}

enum HrToken{
	//Single-character tokens
    leftBracket; rightBracket; equals; comma;
	//Keywords
	variableSection; taskSection;
	//DataTypes
	identifier; value;
	//other
	none; eof;
}

class Token{
	public var type(default,null):HrToken;
	public var lexeme(default,null):String;
	public var line(default,null):Int;
	public var column(default,null):Int;

	public function new(t:HrToken, line:Int, col:Int, ?lex:String = null){
		type = t;
		this.line = line;
		column = col;
		lexeme = lex;
	}

	public function toString(){
		return '${type} |${line}:${column}| |${lexeme}|';
	}
}

class Result {
	public var text:String;
	public var isTaskRef(default,null):Bool;
	public function new(cmd:String, isTaskName:Bool){text = cmd; isTaskRef = isTaskName;}
	public function toString():String{return '${isTaskRef ? "TASK":"Cmd"}:${text}';	}
}

class HrParser {
	//This is what a variable looks like in the value field
	static var repl:EReg = ~/(\|@[A-Za-z0-9_]+\|)/gi;

	//Maps the variables to their values
	var variables:Map<String,String>;

	//Maps the task name to its command
	public var tasks(default,null):Map<String,Array<Result>>;

	//Contains any tasks that are as of yet undefined
	var undefinedTasks:Array<String>;

	public var wasError(default,null):Bool;

	private function new(){
		variables = new Map<String,String>();
		tasks = new Map<String,Array<Result>>();
		undefinedTasks = new Array<String>();
		wasError = false;
	}

	public static function ParseTokens(tokens:Array<Token>):HrParser{
		var parser = new HrParser();
		if(parser.Parse(tokens)) {
			//Expand out all the variable references in the tasks' commands
			for(task in parser.tasks.keys()){
				parser.ExpandVariables(task);
			}
			return parser;
		}

		else return null;
	}

	//Use this function to log errors in this class
	//this allows us to redirect our errors easily
	function logError(err:Dynamic, ?t:Token = null){
		if(t == null)
			Sys.println('Error ${err}');
		else
			Sys.println('Error [${t.line}:${t.column}] ${err}');
		wasError = true;
	}	

	private function Parse(tokens:Array<Token>):Bool{
		//tells which section we're in 0 = variables, 1 = commands
		var section:Int = -1;
		var id:String = "";
		var inArray:Int = 0;

		for(tk in tokens){
			switch(tk.type){
				case HrToken.variableSection:
					section = 0;
				case HrToken.taskSection:
					section = 1;
				case HrToken.identifier:
						if(inArray == 0){
							id = tk.lexeme;
						}
						else {//We're in an array and this is a taskName. Store it for checking
							//An identifier in an array must be a taskName
							tasks[id].push(new Result(tk.lexeme, true));
							undefinedTasks.push(tk.lexeme);
						}
				case HrToken.value:
						if(inArray == 0){
							if(section == 0){ //It is a variable
								if(variables.exists(id)){
									logError('The variable ${id} already exists!');
								}
								else 
									variables.set(id, tk.lexeme);
							}
							else if(section == 1) { //must be a task
								if(tasks.exists(id)){
									logError('The task ${id} already exists!');
								}
								else 
									tasks.set(id, [new Result(tk.lexeme, false)]);
							}
							else{
								logError("Invalid section #");
							}
						}
						else{
							//Values in an array are commands of that id
							tasks[id].push(new Result(tk.lexeme, false));
						}
				case HrToken.leftBracket:
					//If we enter an array, make sure the task doesn't yet exist
					if(tasks.exists(id)){
						logError('The task ${id} already exists!', tk);
					}
					else{ //create an empty array and set its id
						tasks.set(id,[]);
					}
				inArray++;
				case HrToken.rightBracket: inArray--;
				default:
			}
		}

		//Now that we've parsed the tree, check and see if all our tasks are defined
		var status:Bool = true;
		for(undef in undefinedTasks){
			if(!tasks.exists(undef)){
				logError('Unable to find a command for task :${undef}');
				status = false;
			}
		}

		return status;
	}

	//Expand all variables found within a tasks results
	public function ExpandVariables(taskName:String){
	 	if(taskName == null) return;
		var taskSequence = tasks.get(taskName);
		if(taskSequence == null) return;
		for(i in 0 ... taskSequence.length){
			if(taskSequence[i].isTaskRef) continue; //taskReferences dont get expanded
			Expand(taskSequence[i], variables);
		}
	}

	//Gets any task references embedded in this command
	public function GetEmbeddedTaskReferences(cmd:Result):Array<String>{
		if(cmd == null || cmd.isTaskRef) return null;
		else{
			var deps:Array<String> = [];
			repl.map(cmd.text, function(reg:EReg){
				var variableName = reg.matched(1).substring(2, reg.matched(1).length - 1);
				for(key in variables.keys()){
					if(variableName == key){ return "";}
					else{
						//Make sure this taskref is not already in the list of deps AND it isnt a variable
						if(deps.indexOf(variableName) == -1 && !variables.exists(variableName))
							deps.push(variableName);
					}
				}
				return "";
			});
			if(deps.length > 0) return deps;
			else return null;
		}
	}

	public function Expand(res:Result, replacements:Map<String,String>){
		if(res == null || res.isTaskRef || replacements == null) return;

		res.text = repl.map(res.text, function(reg:EReg){
			//Remove the surrounding '|' and the '@'
			var variableName = reg.matched(1).substring(2, reg.matched(1).length - 1);
			// trace('Expand found:${variableName} from |$res|');
			for(key in replacements.keys()){
				if(variableName == key){
					// trace('replacement: |${replacements[key]}|');
					return replacements[key];
				}
			}
			// trace('Expand was unable to find replacement for:${variableName}');
			return reg.matched(1);
		});
	}

	public function toString():String{
		var sb = new StringBuf();
		sb.add("----VARIABLES----\n");
		for(v in variables.keys()){
			sb.add('[${v}] => ${variables[v]}\n');
		}
		sb.add("----TASKS----\n");
		for(v in tasks.keys()){
			sb.add('[${v}] => \n');
			for(t in ${tasks[v]}){
				sb.add('${t.toString()}\n');
			}
		}
		return sb.toString();
	}
}

class HrTokenizer{
	static var WHITESPACE:Array<Int> = ["\t".code, " ".code, "\r".code];
	static var LINE_BREAKS:Array<Int> = ["\n".code, "\r".code];
	static var KEYWORDS:Map<String,HrToken> = ["variables" => HrToken.variableSection, "tasks" => HrToken.taskSection];

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
	var prevTokenType(get,null):HrToken;
	function get_prevTokenType():HrToken { if(tokens.length == 0) return HrToken.none; else return tokens[tokens.length - 1].type;}

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

	function addToken(t:HrToken){
		//  trace('Add ${t} |${lexeme}|');
		tokens.push(new Token(t, line, col - lexemeLength, lexeme));
	}

	function getTokens(){
		while(!isEof()){
			eat(WHITESPACE);
			start = index;
			var c:Int = nextChar();
			switch(c){
				case '#'.code : matchUntil(LINE_BREAKS); //it's a comment
				case '['.code : arrayLevel++; addToken(HrToken.leftBracket);
				case ']'.code : 
					arrayLevel--; 
					if(arrayLevel < 0){ //Unmatched ']'?
						logError('unmatched ]');
					}
					else if(prevTokenType == HrToken.comma){
							logError('invalid comma');
						}
					addToken(HrToken.rightBracket);
				case '='.code :
					if(prevTokenType == HrToken.variableSection || prevTokenType == HrToken.taskSection)
						logError("section headings not allowed on hte left side of an ="); 
					else if(prevTokenType != HrToken.identifier)
						logError("Identifier expected before ="); 
					addToken(HrToken.equals);
				// case ':'.code : addToken(HrToken.colon);
				case ','.code : addToken(HrToken.comma);
				case '\n'.code : start = index; line++; col = 1; if(prevTokenType == HrToken.equals) logError("value required after equals", tokens[tokens.length -1]);
				default:
					//We expect a value after an '='
					if(prevTokenType == HrToken.equals){
						matchUntil(LINE_BREAKS);
						if(lexemeLength > 0)
							addToken(HrToken.value);
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
									else{
										addToken(HrToken.identifier);
									}
								}
								else{
									logError('Expected a taskName identifier after :');
								}
							}
							else{ //otherwise, it must a full command
								matchUntil(LINE_BREAKS);
								if(lexemeLength > 0)
									addToken(HrToken.value);
								else
									logError('Expected a full command');
							}
					}
					else if (isAlpha(c)){
						matchIdentifier();
						if(lexemeLength > 0){
							//is it a keyword?
							var t = KEYWORDS.get(lexeme);
							if(t != null){
								addToken(t);
							}
							else{ //It must be an identifier
								//Was there another identifier before this one? That isn't allowed
								if(prevTokenType == HrToken.identifier){
									logError("Expected an =, not another identifier");
								}
								else
									addToken(HrToken.identifier);
							}
						}
					}
					else{
						logError('Unrecognized token: ${lexeme}');
					}	
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

	function matchIdentifier(){
		while(isAlpha(peek())) nextChar();
	}

	function isEof():Bool{
		return index >= content.length;
	}

	function isAlpha(ch:Int):Bool{
		return (ch >= 'a'.code && ch <= 'z'.code) || (ch >= 'A'.code && ch <= 'Z'.code) || ch == '_'.code;
	}

	function nextChar(): Int {
		index++;
		col++;
		return content.fastCodeAt(index - 1);
	}

	//peeks at the next character in the stream
	//Note: a lookahead of 0 will return the NEXT character
	//      a lookahead of 1 will return the char after that
	function peek():Int {
		if(isEof()) return 0;
		return content.fastCodeAt(index);
	}
}