import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import haxe.io.Path;
using StringTools;

// @author: Pixelbyte Studios
//
//The comments below are meant to utilize my Hix utility to compile/run
//without needing a build.hxml or command line options. Hix can be found here:
//https://github.com/bncastle/hix
//
//::hix -main HR -cpp bin --no-traces -dce full
//::hix:debug -main HR -cpp bin -dce full

//c++ stuff
typedef VoidPointer = cpp.RawPointer<cpp.Void>;

@:cppInclude("Windows.h")
class HR
{
	static inline var VERSION = "0.63";
	static inline var CFG_FILE = "config.hr";
	static inline var STILL_ACTIVE = 259;
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

	// var byteBuffer: haxe.io.Bytes;

	static function main(): Int
	{
		log('\nHR Version $VERSION: A task runner.');
		log("Copyright 2017 Pixelbyte Studios");
		if (Sys.args().length < 1)
		{
			log("===================================");
			log("Usage: HR.exe [-v] ['name of config file'.hr] <task_taskName>");
			log("-v prints out each command as it is executed");
		}

		// var ht = new HrTokenizer();
		// var toks = ht.parseText("test(");
		// for(t in toks)
		//  trace('${t.type}: ${t.lexeme}');

		var h = new HR();
		var retCode:Int = 0;

		//Here we allow the user to specify a different config file name
		//but it must end in .hr. Also, for now, it must be in the same directory
		var cfgFile:String = h.checkArgsForAlternateConfigFilename();
		if(cfgFile == null){
			//Note: We want the config file in the directory where we were invoked!
			cfgFile = HR.findDefaultorFirstConfigFile(Sys.getCwd());
		}

		cfgFile = Path.join([Sys.getCwd(), cfgFile]);

		if (!HR.CheckForConfigFile(cfgFile))
		{
			error('Unable to find "${Path.withoutDirectory(cfgFile)}"');
			log('Make a ${Path.withoutDirectory(cfgFile)} file and put it in your project directory.');
			return -1;
		}

		//Verbose mode?
		h.checkVerboseFlag();

		//Get the task to execute
		var taskName:String = h.checkForTaskName();

		//Parse the config file
		if (!h.ParseConfig(cfgFile))
		{
			return -1;
		}

		//print all tasks in the file
		if (taskName == null)
		{
			h.PrintAvailableTasks(cfgFile);
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

		// byteBuffer = haxe.io.Bytes.alloc(1);
	}

	//Checks for the presence of the verbose flag
	function checkVerboseFlag():Void{
		var arg = Sys.args()[0].trim();
		if(arg == '-v') {
			verbose = true;
			return;
		}
		verbose = false;
	}

	function checkArgsForAlternateConfigFilename():String{
		for(arg in Sys.args()){
			arg = arg.trim();
			if(Path.extension(arg) == "hr") return arg;
		}
		return null;
	}

	function checkForTaskName():String{
		//A task name spec MUST be the last argument so
		var arg = Sys.args()[Sys.args().length - 1].trim();
		if(arg.charAt(0) == '-' || Path.extension(arg) == "hr") return null; //it's a switch, continue
		else return arg; // must be a task spec
	}

	//This is executed when no file is specified
	//if it can find the default CFG_FILE, it will return that
	//otherwise, it will look for another .hr file and return that
	//if it finds no .hr files, it will return CFG_FILE
	static function findDefaultorFirstConfigFile(dir:String): String {
		var files = FileSystem.readDirectory(Path.directory(dir));
		if(files == null || files.length == 0) return CFG_FILE;
		//Sort alphabetically
		files.sort(sortAlphabetically);

		if(files.indexOf(CFG_FILE) > -1) return CFG_FILE;
		
		for(file in files){
			if(Path.extension(file) == "hr") return file;
		}
		return CFG_FILE;
	}

	static function sortAlphabetically(a:String, b:String): Int{
		a = a.toUpperCase();
		b = b.toUpperCase();
		if(a < b) return -1;
		else if(a > b) return 1;
		else return 0;
	}

	function ParseConfig(cfgFile:String): Bool{
		tokens = tokenizer.parseFile(cfgFile);

		//Print out all our tokens
		// for(t in tokens)
		// trace('${t.type}: ${t.lexeme}');

		if(tokens != null && !tokenizer.wasError){
			parser = HrParser.ParseTokens(tokens);
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
			// Sys.println(tasks[i].text);
				stack.push(tasks[i].text);
			}
			else{ //it must be a command so get those deps
				var cmdDeps = parser.GetEmbeddedTaskReferences(tasks[i]);

				//now we need to go through these and get their deps
				if(cmdDeps != null){
					for(j in 0 ... cmdDeps.length){ //if this dep is not already on the stack, push it
						if(stack.indexOf(cmdDeps[j]) == -1){
							// Sys.println(taskName + " - " + cmdDeps[j]);
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
			
			// trace('Dependencies for ${task}:');
			// for(d in deps){
			// 	trace(d);
			// }
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
				// trace('Expand for ${tasks[i]}');
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

	// function Pipe(sourceInput:haxe.io.Input, filePipe:haxe.io.Output, stringPipe:StringBuf) : Bool{
	// 	try{
	// 		if(sourceInput.readBytes(byteBuffer, 0 ,1) <= 0)
	// 			return false;
	// 		else{
	// 			filePipe.writeByte(byteBuffer.get(0));
	// 			stringPipe.addChar(byteBuffer.get(0));
	// 			// if(byteBuffer.get(0) == '\n'.code) return false;
	// 			return true;
	// 		}
	// 	}
	// 	catch(e:Dynamic){
	// 		// Sys.print('!');			
	// 		return false;
	// 	}
	// }

	function Pipe(sourceInput:haxe.io.Input, filePipe:haxe.io.Output, stringPipe:StringBuf) : Bool{
		try{
			var ch = sourceInput.readString(1);
			filePipe.writeString(ch);
			stringPipe.add(ch);
			return true;
		}
		catch(e:Dynamic){
			return false;
		}
	}

	function RunCommand(taskName:String, cmd:String, showOutput:Bool):Int{
		//If we are in verbose mode, print the command too
		if(verbose){
			log('\nRun: $cmd');
		}

		var proc = new Process(cmd);
		var procHandle:VoidPointer = getProcessHandle(proc.getPid());

		var iserror:Bool = false;
		var output:StringBuf = new StringBuf();

		//proc.exitCode(false) doesn't work in WINDOWS
		//so I've tapped into the winapi in order to
		//report output from the process as it happens
		while(procRunning(procHandle)){
			if(!iserror && !Pipe(proc.stdout, Sys.stdout(), output)) iserror = true;
			else if(iserror && !Pipe(proc.stderr, Sys.stderr(), output)) iserror = false;
			// if(!iserror && (!Pipe(proc.stdout, Sys.stdout(), output) || Pipe(proc.stderr, Sys.stderr(), output))){
			// 		iserror = true;
			// }	
			// else if(iserror && !Pipe(proc.stderr, Sys.stderr(), output)){
			// 	iserror = false;
			// }

			//Don't hog the CPU
			// Sys.sleep(0.001);
		}
		closeHandle(procHandle);

		//Get any leftover output from the process
		var leftover = proc.stdout.readAll().toString();
		output.add(leftover);
		if(showOutput) Sys.print(leftover);
		leftover = proc.stderr.readAll().toString();
		if(showOutput) Sys.print(leftover);
		output.add(leftover);

		//When the process is done (i.e. no more output written to stdout or stderr), get the exit code
		var retcode:Int = proc.exitCode();
		proc.close();

		 if(output.length > 0){
		 	if(taskName != null){
		 		// trace('Set results for $taskName => |$output|');
		 		taskResults.set(taskName, output.toString().rtrim());
		 	}
		 }

		return retcode;
	}

	function PrintAvailableTasks(cfgFilename:String){
		log('');
		log('Available Tasks in "${Path.withoutDirectory(cfgFilename)}"');
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

	// static var exit_code:Int->Int->Bool = cpp.Lib.load("kernel32", "GetExitCodeProcess", 2);
	@:functionCode("
		return OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, procId);
	")
	static function getProcessHandle(procId:Int):VoidPointer{
		#if !cpp
			return null;
		#else
			return null;
		#end
	}

	//My external C functions////////////////////////
	@:functionCode("
		CloseHandle(handle);
	")
	static function closeHandle(handle:VoidPointer){

	}

	//Gets the exit code from a given process id
	@:functionCode("
		DWORD exitCode;
		GetExitCodeProcess(handle, &exitCode);
		return exitCode == STILL_ACTIVE;
	")
	static function procRunning(handle:VoidPointer):Bool{
			#if !cpp
				return false;
			#else
				return false;
			#end
	}
}

enum HrToken{
	//Single-character tokens
    leftBracket; rightBracket; equals; comma; leftParen; rightParen;
	//Keywords
	variableSection; taskSection;
	//DataTypes
	identifier; value;
	//other
	none; eof;
}

enum ConfigSection{ none; variables; tasks;}

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

class ParameterizedTask{
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

class Result {
	public var text:String;
	public var isTaskRef(default,null):Bool;


	public function new(cmd:String, isTaskName:Bool){text = cmd; isTaskRef = isTaskName;}
	public function toString():String{return '${isTaskRef ? "TASK":"Cmd"}:${text}';	}
}

class HrParser {
	//This is what a variable looks like in the value field
	// static var repl:EReg = ~/(\|@[A-Za-z0-9_]+\|)/gi;
	//A variable is @variable
	static var varRegex:EReg = ~/@([A-Za-z0-9_]+)/gi;
	static var paramTaskRegex:EReg = ~/_([A-Za-z0-9_]+\([^\)]+\))/gi;

	//Maps the variables to their values
	var variables:Map<String,String>;

	//Maps the task name to its command
	public var tasks(default,null):Map<String,Array<Result>>;

	public var parameterizedTasks(default, null): Map<String, ParameterizedTask>;
	var pTaskTokenizer:HrTokenizer;

	//Contains any tasks that are as of yet undefined
	var undefinedTasks:Array<String>;

	public var wasError(default,null):Bool;

	private function new(){
		variables = new Map<String,String>();
		tasks = new Map<String,Array<Result>>();
		parameterizedTasks = new Map<String, ParameterizedTask>();
		undefinedTasks = new Array<String>();
		pTaskTokenizer= new HrTokenizer();
		wasError = false;
	}

	public static function ParseTokens(tokens:Array<Token>):HrParser{
		var parser = new HrParser();
		if(parser.Parse(tokens)) {
			//Expand out all the variable references in the tasks' commands
			for (v in parser.variables.keys()){
				parser.ExpandVariablesWithinVariable(v);
			}
			for(pt in parser.parameterizedTasks){
				parser.ExpandVariablesWithinParameterizedTask(pt);
			}
			for(task in parser.tasks.keys()){
				parser.ExpandParameterizedTasksWithinTask(task);
				parser.ExpandVariablesWithinTask(task);
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
		if(tokens == null || tokens.length < 1){
			logError("No tokens to parse!");
			return false;
		}

		//tells which section we're in 0 = variables, 1 = commands
		var section:ConfigSection = ConfigSection.none;
		var id:String = "";
		var inArray:Int = 0;
		var tkIndex = 0;

		var current = function():Token { return tkIndex < tokens.length ? tokens[tkIndex] : null;}
		var exists = function(type: HrToken, startIndex:Int = 0):Bool { 
			startIndex = cast Math.min(Math.max(0, startIndex), tokens.length - 1); 
			for(i in startIndex...tokens.length) if(tokens[i].type == type) return true;
			return false;
			}
		var previous = function():Token { return tkIndex - 1 >= 0 ? tokens[tkIndex - 1] : null;}
		var next = function():Token { return tkIndex + 1 < tokens.length ? tokens[tkIndex + 1] : null;}
		
		var inParameterList:Bool = false;	
		var parameterArray:Array<String> = null;

		while(current() != null){
			var tk = current();
			switch(tk.type){
				case HrToken.variableSection:
					section = ConfigSection.variables;
				case HrToken.taskSection:
					section = ConfigSection.tasks;
				case HrToken.identifier:
						if(inArray == 0){
							if(!inParameterList){
								id = tk.lexeme;
							}
							else{
								parameterArray.push(tk.lexeme);
							}
						}
						else {
							//We're in an array and this is a taskName. Store it for checking
							//An identifier in an array must be a taskName
							tasks[id].push(new Result(tk.lexeme, true));
							undefinedTasks.push(tk.lexeme);
						}
				case HrToken.value:
						if(inArray == 0){
							if(section == ConfigSection.variables){ //It is a variable
								if(variables.exists(id)){
									logError('The variable ${id} already exists!');
								}
								else 
									variables.set(id, tk.lexeme);
							}
							else if(section == ConfigSection.tasks) { //must be a task
								if(tasks.exists(id)){
									logError('The task ${id} already exists!');
								}
								else if(parameterizedTasks.exists(id)){
									logError('The parameterized task ${id} already exists!');
								}
								else {
									if(parameterArray != null){
										if(inParameterList){
											logError("Expected ')'", tk);
											parameterArray = null;
										}
										else{
											var pTask = new ParameterizedTask(id, tk.lexeme, parameterArray);
											//trace('Found parameterized Task: ${pTask.toString()}');
											parameterArray = null;
											parameterizedTasks.set(id, pTask);
											// trace('call: ${pTask.call(["input.file", "tak.out"])}');
										}
									}
									else{
										//trace('task found: ${id}');
										tasks.set(id, [new Result(tk.lexeme, false)]);
									}
								}
							}
							else{
								logError("Invalid section type!");
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
				case HrToken.leftParen:  if(previous().type == HrToken.identifier) inParameterList = true; parameterArray = new Array<String>();
				case HrToken.rightParen: inParameterList = false;
				// case HrToken.comma: 
				default:
			}
			tkIndex++;
		}

		if(inParameterList){
			logError("Expected ')'", previous());
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
	public function ExpandVariablesWithinTask(taskName:String){
	 	if(taskName == null || taskName == "") return;
		var taskSequence = tasks.get(taskName);
		if(taskSequence == null) return;

		//Go through all the sequences in this task
		for(i in 0 ... taskSequence.length){
			if(taskSequence[i].isTaskRef) continue; //taskReferences don't get expanded
			Expand(taskSequence[i], variables);
		}
	}

	public function ExpandVariablesWithinVariable(variableName:String){
		if(variableName == null || variableName == "" || !variables.exists(variableName) ) return;
		variables[variableName] = varRegex.map(variables[variableName], function(reg:EReg){
			var vname = reg.matched(1);
			if(variables.exists(vname)){
				return variables[vname];
			}
			else
				return variables[variableName];
		});
		//trace('Variable:$variableName => $value => ${variables[variableName]}');
	}

	public function ExpandVariablesWithinParameterizedTask(parametrizedTask:ParameterizedTask){
		if(parametrizedTask == null ) return;
		parametrizedTask.text = varRegex.map(parametrizedTask.text, function(reg:EReg){
			var variableName = reg.matched(1);
			if(variables.exists(variableName)){
				return variables[variableName];
			}
			else
				return parametrizedTask.text;
		});
		//  trace('Task:${parametrizedTask.name} => ${parametrizedTask.text} ');
	}

	public function ExpandParameterizedTasksWithinTask(taskName:String){
	 	if(taskName == null || taskName == "") return;
		var taskSequence = tasks.get(taskName);
		if(taskSequence == null) return;

		for(i in 0 ... taskSequence.length){
			if(taskSequence[i].isTaskRef) continue; //taskReferences don't get expanded
			taskSequence[i].text = paramTaskRegex.map(taskSequence[i].text, 
			function (reg:EReg){
				var ptaskName = reg.matched(1).substr(0, reg.matched(1).indexOf('('));
				var paramGlob = reg.matched(1).substr(ptaskName.length + 1);
				paramGlob = paramGlob.substr(0, paramGlob.length -1);
				paramGlob = paramGlob.trim();

				// trace('ptaskName: ${ptaskName} other: ${paramGlob}');
				//trace('full: ${ptaskName}(${reg.matched(2)})');

				if(parameterizedTasks.exists(ptaskName)){
					//See if there are any parameters
					var params:Array<String> = paramGlob.split(",");
					for(i in 0 ... params.length){
						params[i] = params[i].trim();
					}

					var ptask = parameterizedTasks[ptaskName];
					var output:String = ptask.call(params);

					//TODO: Make sure the correct number of parameters are given
					// if(ptask.NumParams != params.length) 
					return output;
				}
				else{
					// trace('parameterized task: $ptaskName was not found!');
					return reg.matched(0);
				}
			});
			//trace('X:${taskSequence[i].text}');
		}
	}

	public function Expand(res:Result, replacements:Map<String,String>){
		if(res == null || res.isTaskRef || replacements == null) return;

		res.text = varRegex.map(res.text, function(reg:EReg){
			var variableName = reg.matched(1);
			// trace('Expand found:${variableName} from @$res');
			for(key in replacements.keys()){
				// trace('replacement: [$key] var:[$variableName]');
				if(variableName == key){
					// trace('replacement: |${replacements[key]}|');
					return replacements[key];
				}
			}
			 trace('Expand was unable to find replacement for:${variableName}');
			return res.text;
		});
		// trace('body: ${res.text}');
	}

	//Gets any task references embedded in this command
	public function GetEmbeddedTaskReferences(cmd:Result):Array<String>{
		if(cmd == null || cmd.isTaskRef) return null;
		else{
			var deps:Array<String> = [];
			varRegex.map(cmd.text, function(reg:EReg){
				var variableName = reg.matched(1);
				for(key in variables.keys()){
					if(variableName == key){ return "";}
				}

				//Make sure this taskref is not already in the list of deps AND it isnt a variable
				if(deps.indexOf(variableName) == -1 && !variables.exists(variableName))
					deps.push(variableName);
				return "";
			});
			if(deps.length > 0) return deps;
			else return null;
		}
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
	function get_prevTokenType():HrToken { return tokens.length - 1 >= 0 ? tokens[tokens.length - 1].type : HrToken.none;}

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
				case '('.code : addToken(HrToken.leftParen);
				case ')'.code : addToken(HrToken.rightParen);
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
						logError("section headings not allowed on the left side of an ="); 
					else if(prevTokenType != HrToken.identifier  && prevTokenType != HrToken.rightParen)
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