import sys.FileSystem;
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
	static inline var VERSION = "0.71";
	static inline var CFG_FILE = "config.hr";
	static inline var STILL_ACTIVE = 259;
	static inline var ERR_TASK_NOT_FOUND = -1025;
	static inline var ERR_CYCLIC_DEPENDENCE = -1026;
	static inline var ERR_NO_TASKS_FOUND = -1027;
 	static inline var ERR_ILLEGAL_TASK_REF= -1028;

	var verbose:Bool = false;
	var tokenizer(default,null):HrTokenizer;
	var parser:HRParser;
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
		//Grab the args (We'll be manipulating this) remove spaces and empty entries
		var args = Sys.args().map(function(arg) {return arg.trim();}).filter(function(a){ return (a != null && a != "");});

		//Here we allow the user to specify a different config file name
		//but it must end in .hr. Also, for now, it must be in the same directory
		var cfgFile:String = h.getAlternateConfigName(args);
		if(cfgFile == null){
			//Note: We want the config file in the directory where we were invoked!
			cfgFile = HR.findDefaultorFirstConfigFile(Sys.getCwd());
		}

		if(cfgFile != null)
			log('Using file: $cfgFile');
		//Add the full path to the config filename we found
		cfgFile = Path.join([Sys.getCwd(), cfgFile]);

		if (!HR.CheckForConfigFile(cfgFile))
		{
			error('Unable to find "${Path.withoutDirectory(cfgFile)}"');
			log('Make a ${Path.withoutDirectory(cfgFile)} file and put it in your project directory.');
			return -1;
		}

		//Verbose mode?
		h.checkVerboseFlag(args);

		//Get the task to execute
		var taskName:String = h.checkForTaskName(args);

		//Any args left will be sent to the task as taks args

		//Parse the config file
		if (!h.ParseConfig(cfgFile, args))
		{
			error('config file issues\n');
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


		trace('Running task: $taskName\n');
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
	function checkVerboseFlag(args:Array<String>):Void{
		if(args == null || args.length == 0) return;
		if(args[0] == '-v') {
			args.splice(0,1);
			verbose = true;
			return;
		}
		verbose = false;
	}

	function getAlternateConfigName(args:Array<String>):String {
		if(args == null || args.length == 0) return null;
		for(i in 0...args.length){
			if(Path.extension(args[i]) == "hr") {
				var cfg = args[i];
				args.splice(i, 1);
				return cfg;
			}
		}
		return null;
	}

	function checkForTaskName(args:Array<String>):String {
		if(args == null || args.length == 0) return null;
		//A task name should be the first argument by the time we're done looking for switches
		var arg = args[0].trim();
		if(Path.extension(arg) == "hr") return null; //it's a switch, continue
		else {
			args.splice(0,1);
			return arg; // must be a task spec
		}
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

	function ParseConfig(cfgFile:String, taskArgs:Array<String>): Bool{
		tokens = tokenizer.parseFile(cfgFile);

		//Print out all our tokens
		// for(t in tokens)
		// trace('${t.type}: ${t.lexeme}');

		if(tokens != null && !tokenizer.wasError){
			parser = HRParser.ParseTokens(tokens, taskArgs);
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
				parser.ExpandTaskArgs(tasks[i]);

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
			log('\nRunTask: ${taskName} => ${cmd}');
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
			//Only show tasks that arent "hidden"
			//a task beginning with an underscore '_' is hidden
			//and wont be displayed but it can still be executed
			if(taskName.charCodeAt(0) != '_'.code)
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