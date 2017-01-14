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
	static inline var VERSION = "0.24";
	static inline var CFG_FILE = "config.hr";
	static inline var ERR_TASK_NOT_FOUND = -1025;

	var verbose:Bool = false;
	var parser(default,null):HrParser;

	//This holds any taks we are in the Process
	//of running. A task is put on here if it depends on another
	//task. This way we can check for cyclic references and catch them
	var taskStack:Array<String>;

	static function main(): Int
	{
		Sys.println('\nHR Version $VERSION: A task runner.');
		Sys.println("Copyright 2016 Pixelbyte Studios");

		//Note this: We want the config file in the directory where we were invoked!
		var cfgFile:String = Sys.getCwd() + CFG_FILE;
		var printTasks:Bool = false;

		if (Sys.args().length < 1)
		{
			Sys.println("===================================");
			Sys.println("Usage: HR.exe [-v] <task_taskName>");
			Sys.println("-v prints out each command as it is executed");
			// Sys.println("-t (prints a list of valid tasks)");

			if (!HR.CheckForConfigFile(cfgFile))
			{
				Sys.println('Make a $CFG_FILE file and put it in your project directory.');
				return -1;
			}
			else{
				Sys.println("");
				printTasks = true;
			}
		}

		var h = new HR();
		var taskIndex = 0;

		//Try  to parse the HR config file
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

		if (Sys.args()[0] == "-v")
		{
			h.verbose = true;
			taskIndex++;
		}

		var subTask:String = Sys.args()[taskIndex];
		Sys.println(subTask);
		var retCode:Int = h.RunTask(subTask);
		if (retCode == ERR_TASK_NOT_FOUND)
		{
			Sys.println('Task: $subTask not found!');
			return -1;
		}
		else if ( retCode != 0)
		{
			// Sys.println('Error running task: $subTask');
			return -1;
		}

		return retCode;
	}

	public function new()
	{
		//Create a new parser
		parser = new HrParser();
		taskStack = new Array<String>();
	}

	function ParseConfig(cfgFile:String): Bool
	{
		return parser.Parse(cfgFile);
	}

	function RunTask(taskName: String):Int
	{
		var index = KeyValues.KeyIndex(taskName, parser.tasks);
		if(index < 0){
			Sys.println('No command found for task: $taskName');
			return ERR_TASK_NOT_FOUND;
		}

		var task = parser.tasks[index];
		var retCode:Int = 0;

		for(i in 0...task.values.length){

			//See if the command is itself a task. If it is, run it
			if(task.values[i].charAt(0) == ":")
			{
				var subTask = task.values[i].substr(1);
				retCode = RunTask(subTask);
				if (retCode == ERR_TASK_NOT_FOUND)
				{
					Sys.println('Unable to run task: $subTask from task: $taskName. The $subTask task does not exist!');
					taskStack.remove(taskName);
					return -1;
				}
				else if(retCode != 0){
					Sys.println('Error in sub-task: $subTask from task: $taskName. $subTask returned $retCode');
					taskStack.remove(taskName);
					return retCode;
				}
			}
			else
			{
				//First, get dependencies for this task
				//trace('Get Dependencies from ${parser.tasks.length} tasks');
				var dependencies = task.GetDependencies(parser.tasks);

				if(dependencies.length > 0){
					trace('$taskName numdeps: ${dependencies.length}');
					//We need to run these first, but we must also
					//push the current task onto the taskStack
					if(taskStack.indexOf(taskName) > -1){
						//Find the cyclical dependency
						for(i in 0... dependencies.length){
							var cycindex = taskStack.indexOf(dependencies[i]);
							if(cycindex > -1){
								Sys.println('Error: Cyclical dependency $taskName <=> ${dependencies[i]}');
								return -1;
							}
						}

						Sys.println('Task dependency error: $taskName');
						return -1;
					}
					else
						taskStack.push(taskName);

					trace('$taskName depends on:');

					for(i in 0... dependencies.length){
						trace('${dependencies[i]}');

						//Run the dependency
						retCode = RunTask(dependencies[i]);
						if(retCode != 0){
							Sys.println('Error running dependency: ${dependencies[i]} in $taskName');
							taskStack.remove(taskName);
							return retCode;
						}
					}
				}

				//See if the command has any references to other task outputs
				//if so, add the task output in
				parser.UpdateCommandWithResults(taskName);

				//If we are in verbose mode, print the command too
				if(verbose)
					Sys.println(task.values[i]);

				// var args = t.value.split(' ');
				// var cmd = args.shift();
				var proc = new Process(task.values[i]);
				var output:String = proc.stdout.readAll().toString();
				var err:String = proc.stderr.readAll().toString();
				var retcode:Int = proc.exitCode();

				proc.close();

				if(output.length > 0)
					Sys.print(output);
				if(err.length > 0)
					Sys.print(err);

				//May want to remove this later?
				//if(output.length < 512)
				//Trim the end of the output to remove any newline characters as that would
				//totally screw up using the output of this task in another!
				parser.AddResult(task.key, output.rtrim());


				taskStack.remove(taskName);

				if (retcode != 0) return retcode;
			}
		}
		return 0;
	}

	function PrintAvailableTasks()
	{
		Sys.println("Available Tasks:");
		for	(t in parser.tasks)
		{
			Sys.println(t.key);
		}
	}

	//function IsTask(taskName:String)
	//{
	//	for (t in tasks)
	//	{
	//		if (taskName.toLowerCase() == t.taskName.toLowerCase()) return true;
	//	}
	//	return false;
	//}

	static function CheckForConfigFile(cfgFile:String): Bool
	{
		//Check for a valid config file
		if (!FileSystem.exists(cfgFile))
		{
			Sys.println("Config file " + cfgFile + " doesn't exist.");
			return false;
		}
		return true;
	}
}

enum ParserState{
	Init;
	SectionTaskNameSearch;
	KeySearch;
	ValueSearch;
	FinishSuccess;
	FinishFail;
}

class KeyValues{
	public var key(default, null):String;
	public var values(default, null):Array<String>;

	//This is what a variable looks like in the value field
	static var repl:EReg = ~/(\|@[A-Za-z0-9_-]+\|)/gi;

	public function new(taskName:String, val:String, vals:Array<String> = null){
		key = taskName;

		if(vals == null){
			values = new Array<String>();
			values.push(val);
		}
		else{
			values = vals;
		}
	}

	public function ExpandVariables(replacements:Array<KeyValues>){
		if(replacements == null || replacements.length == 0) return;
		// trace(key + "=" + value);

		for(i in 0...values.length){
			//Try to replace any that exist in our variables map and are in the command
			values[i] = repl.map(values[i], function (reg:EReg) {
				//Remove the surrounding '|' and the '@'
				var variableName = reg.matched(1).substring(2, reg.matched(1).length - 1);

				for(i in 0...replacements.length){
					if(variableName == replacements[i].key)
					{
						//Sys.println("-->" + replacements[i].value);
						return replacements[i].values[0];
					}
				}
				return reg.matched(1);
			});
			// Sys.println("::" + value);
		}
	}

	//Returns an array of task taskNames on which this command is dependent
	//
	public function GetDependencies(tasks:Array<KeyValues>): Array<String>{
		var dependents = new Array<String>();
		if(tasks == null || tasks.length == 0) return dependents;

		for(i in 0...values.length){
			//check and see if any task taskName appears in the command
			//if it does, add it to the List
			trace('value: ${values[i]}');
			repl.map(values[i], function(reg:EReg){
				//Remove the surrounding '|' and the '@'
				var variableName = reg.matched(1).substring(2,reg.matched(1).length - 1);

				//Is the variable we just found in the tasks list?
				var index = KeyValues.KeyIndex(variableName, tasks);
				if(index > - 1 && dependents.indexOf(variableName) == -1){
					//Make sure the matching task is not the same task as this one!
					if(tasks[index].key != key){
						dependents.push(variableName);
					}
				}
				return reg.matched(1);
			});
		}

		return dependents;
	}

	public static function KeyIndex(key:String, array:Array<KeyValues>): Int{
		if(array == null) return -1;
		for(i in 0...array.length){
			if(array[i].key == key) return i;
		}
		return -1;
	}
}

// class KeyValuess{
// 	public var key(default, null):String;
// 	public var values:Array<String>;
// 	public function new(taskName:String){
// 		key = taskName;
// 		values = new Array<String>();
// 	}

// 	public function AddValue(value:String){
// 		values.push(value);
// 	}
// }

class HrParser{

	static inline var VARIABLES_SECTION = "variables";
	static inline var TASKS_SECTION = "tasks";

	//ParserState
	var pos: Int;
	// var column: Int;
	// var line: Int;
	var text:String;
	var state: ParserState;
	var currentSectiontaskName:String;
	var currentKey:String;
	var currentValue:String;

	//Parser results
	//Holds any variables declared
	var variables:Array<KeyValues>;
	//Holds the tasks and their respective commands
	public var tasks:Array<KeyValues>;
	//Holds the taks outputs
	var taskOutputs:Array<KeyValues>;

	static inline function  nonWordChars() { return [' ', '=', '\r','\n', '{', '}', '[', ']']; }

	public function new() {
	}

	function initialize(){
		variables = new Array<KeyValues>();
		tasks = new Array<KeyValues>();
		taskOutputs = new Array<KeyValues>();

		state = ParserState.Init;
		pos = 0;
		currentSectiontaskName = '';
		currentKey = '';
		currentValue = '';
		// column = 0;
		// line = 0;
	}

	public function Parse(cfgFile:String): Bool{
		if(!FileSystem.exists(cfgFile)) return false;
		initialize();
		text = File.getContent(cfgFile);
		if(text.length == 0) return false;
		while(pos < text.length){
			switch(state){
				case Init:
					trace("Init");
					state = ParserState.SectionTaskNameSearch;
				case SectionTaskNameSearch:
					trace("SectionTaskNameSearch");
					currentSectiontaskName = FindWord(nonWordChars(), true);
					if(currentSectiontaskName.length == 0){
						Sys.println("Unable to find a section taskName!");
						state = ParserState.FinishFail;
					}
					else{
						trace('Found section: $currentSectiontaskName');
						CheckForChar('{', ParserState.KeySearch, ParserState.FinishFail);
					}
				case KeySearch:
					currentKey = FindWord(nonWordChars(), true);
					if(currentKey.length == 0){
						trace("Didn't find any more keys in this section.");
						CheckForChar('}', ParserState.SectionTaskNameSearch, ParserState.FinishFail);
					}
					else{
						if(!isNextChar('=')){ //Check for equals
							Sys.println("Error: Expected '='!");
							state = ParserState.FinishFail;
						}
						else{
							trace('Found key: $currentKey');
							eatWhitespace();
							state = ParserState.ValueSearch;
						}
					}
				case ValueSearch:
					trace("ValueSearch");
					//Is it an array??
					if(isNextChar('[')){
						var cmds = new Array<String>();
						while (!isNextChar(']') && pos < text.length){
							eat([',',' ','\n','\r']);
							if(isNextChar(':')){
								var taskLabel = FindWord([' ', ',', '\r', '\n', ']'], false);
								if(taskLabel.length == 0){
									Sys.println("Error: Unable to find a valid task label");
									state = ParserState.FinishFail;
									break;
								}
								else{
									cmds.push(':$taskLabel');
								}
							}
							else
							{
								Sys.println("Error: Expected a ':'. Arrays can only contain tasks, and task names must be preceeded by a ':'");
								state = ParserState.FinishFail;
								break;
							}
						}
						if(state == ParserState.FinishFail) continue;
						else{
							//We successfully parsed an array of commands
							tasks.push(new KeyValues(currentKey, null, cmds));
							state = ParserState.KeySearch;
							continue;
						}
					}


					//Otherwise it must be just a value then
					//A value is constrained to be on a single line
					currentValue = FindWord(['\r','\n'], false);
					if(currentValue.length == 0){
						Sys.println("Error:Unable to find a value for $currentKey!");
						state = ParserState.FinishFail;
					}
					else{
						trace('Found value: $currentValue');
						if(currentSectiontaskName == VARIABLES_SECTION){
							variables.push(new KeyValues(currentKey, currentValue));
						}
						else if(currentSectiontaskName == TASKS_SECTION){
							if(KeyValues.KeyIndex(currentKey, tasks) > -1){
								Sys.println('Error: task \'$currentKey\' already exists!');
								state = ParserState.FinishFail;
								continue;
							}
							else{
								tasks.push(new KeyValues(currentKey, currentValue));
							}
						}
						CheckForChar('}', ParserState.SectionTaskNameSearch, ParserState.KeySearch);
					}
				case FinishSuccess:
					trace("FinishSuccess");
					return true;
				case FinishFail:
					trace("FinishFail");
					return false;
			}
		}

		 if(state == ParserState.FinishFail){
			 return false;
		 }

		//Replace any variables with their contents
		for(i in 0...tasks.length){
			tasks[i].ExpandVariables(variables);
		}
		return true;
	}

	function IsEof(){ return pos >= text.length;}

	function CheckForChar(ch:String, trueState:ParserState, falseState:ParserState):Bool{
		if(!isNextChar(ch)){
			//If we didn't find it before the end of the file, then Error!
			if(IsEof()){
				Sys.println('Error: missing \'$ch\'');
				state = ParserState.FinishFail;
			}
			else{
				//trace('Did not find $ch');
				state = falseState;
			}
			return false;
		}
		else{
			trace('Found $ch');
			state = trueState;
			return true;
		}
	}

	function FindWord(excluded:Array<String>, commentsAllowed:Bool):String{
		eatWhitespace();
		//Can we have comments at the very start?
		if(commentsAllowed){
			while (text.charAt(pos) == '#'){
				eatline(); eatWhitespace();
			}
		}

		var taskName:StringBuf = new StringBuf();
		var c:String='';
		while(pos < text.length){
			c = text.charAt(pos);
			if(excluded.indexOf(c) > -1){
				break;
			 }
			else
				taskName.addChar(text.charCodeAt(pos));
			pos++;
		}
		eatWhitespace();
		return taskName.toString();
	}

	function eatWhitespace(){
		eat([' ', '\n' ,'\r']);
	}

	function eat(yummyChars:Array<String>){
		while(pos < text.length){
			if(yummyChars.indexOf(text.charAt(pos)) > -1 ) pos++;
			else break;
		}
	}

	function isNextChar(c:String): Bool{
		eatWhitespace();
		if(pos < text.length && text.charAt(pos) == c){
			pos++;
			return true;
		}
		return false;
	}

	function eatline(){
		var c:String ='';
		while(pos < text.length){
			c = text.charAt(pos++);
			 if(c == '\n' || c == '\r') {
				 eatWhitespace();
				 break;
			 }
		}
	}

	///
	//Updates a task's command with any other task results
	//that they refer to
	public function UpdateCommandWithResults(tasktaskName:String){
		var index = KeyValues.KeyIndex(tasktaskName, tasks);
		if(index == -1 ) return;
		tasks[index].ExpandVariables(taskOutputs);
	}

	public function AddResult(subTask:String, result:String){
		var index = KeyValues.KeyIndex(subTask, taskOutputs);
		if(index == -1){
			taskOutputs.push(new KeyValues(subTask, result));
		}
	}
}
