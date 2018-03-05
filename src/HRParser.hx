using StringTools;

enum ConfigSection{ none; variables; tasks; templates;}

class HRParser {

	//This is what a variable looks like in the value field
	// static var repl:EReg = ~/(\|@[A-Za-z0-9_]+\|)/gi;
	//A variable is @variable
	static var varRegex:EReg = ~/:([A-Za-z_][A-Za-z0-9_]+):/gi;
	// static var taskVarRegex:EReg = ~/@([A-Za-z_][A-Za-z0-9_]+)/gi;
	static var taskArgsRegex:EReg = ~/@([0-9]+)(?:\[(.*?)\])?/gi;
	static var templatesRegex:EReg = ~/@([A-Za-z_][A-Za-z0-9_]+\([^\)]*\))/gi;

	//Maps the variables to their values
	var variables:Map<String,String>;
	//These are args specified on that command line that are passed to our task
	var task_args:Array<String>;

	//Maps the task name to its command
	public var tasks(default,null):Map<String,Array<Result>>;

	public var templates(default, null): Map<String, Template>;

	//Contains any tasks that are as of yet undefined
	var undefinedTasks:Array<String>;

	public var wasError(default,null):Bool;

	private function new(taskArgs:Array<String>){
		variables = new Map<String,String>();
		task_args = taskArgs;
		tasks = new Map<String,Array<Result>>();
		templates = new Map<String, Template>();
		undefinedTasks = new Array<String>();
		wasError = false;

		//Special variables that are set by HR and encased between a '_' on each end 
		var cwd = Sys.getCwd();
		if(cwd.charAt(cwd.length -1 ) == '/'){
			cwd = cwd.substr(0, cwd.length - 1);
			cwd += '\\';
		}

		///Set any internally-defined variables here:
		variables.set("_cwd_", cwd);
	}

	public static function ParseTokens(tokens:Array<Token>, taskArgs:Array<String>):HRParser{
		var parser = new HRParser(taskArgs);
		if(parser.Parse(tokens) && !parser.wasError) {	
			parser.ExpandVariablesAndArgs();
			if(parser.wasError) return null;		
			return parser;
		}
		else return null;
	}

	function ExpandVariablesAndArgs() {
		if(wasError) return;

		//Expand out all the variable references in the tasks' commands
		// trace('HRParser: Expanding variables within variables');
		for (v in variables.keys()){
			ExpandVariablesWithinVariable(v);
			ExpandTaskArgsWithinVariable(v);
		}

		if(wasError) return;

		// trace('HRParser: Expanding variables within templates');
		for(pt in templates){
			ExpandVariablesWithinTemplate(pt);
			ExpandTemplatesWithinTemplate(pt);
		}

		if(wasError) return;

		// trace('HRParser: Expanding templates within task and variables within tasks');
		for(task in tasks.keys()){
			ExpandTemplatesWithinTask(task);
			ExpandVariablesWithinTask(task);
		}
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
		// var exists = function(type: HRToken, startIndex:Int = 0):Bool { 
		// 	startIndex = cast Math.min(Math.max(0, startIndex), tokens.length - 1); 
		// 	for(i in startIndex...tokens.length) if(tokens[i].type == type) return true;
		// 	return false;
		// 	}
		var previous = function():Token { return tkIndex - 1 >= 0 ? tokens[tkIndex - 1] : null;}
		// var next = function():Token { return tkIndex + 1 < tokens.length ? tokens[tkIndex + 1] : null;}
		
		var inParameterList:Bool = false;	
		var parameterArray:Array<String> = null;

		//Parse all the tokens but stop on the 1st error we encounter
		//Note: I might change this back to allow complete parsing even with errors
		while(current() != null && !wasError){
			var tk = current();
			switch(tk.type){
				case HRToken.variableSection:
					section = ConfigSection.variables;
				case HRToken.taskSection:
					section = ConfigSection.tasks;
				case HRToken.templateSection:
					section = ConfigSection.templates;
				case HRToken.identifier:
						if(section == ConfigSection.templates){
							if(!inParameterList){
								id = tk.lexeme;
							}
							else{
								parameterArray.push(tk.lexeme);
							}
						}
						else{
							if(inArray == 0){
									id = tk.lexeme;
							}
							else {
								//We're in an array and this is a taskName. Store it for checking
								//An identifier in an array must be a taskName
								tasks[id].push(new Result(tk.lexeme, true));
								undefinedTasks.push(tk.lexeme);
							}
						}
				case HRToken.value:
						if(inArray == 0){
							if(section == ConfigSection.variables){ //It is a variable
								if(variables.exists(id)){
									logError('The variable "${id}" already exists!');
								}
								else if(id.indexOf("_") == 0 && id.endsWith("_")){
									logError('Variable : "${id}" cannot be surrounded by _.');
								}
								else 
									variables.set(id, tk.lexeme);
							}
							else if(section == ConfigSection.tasks) { //must be a task
								if(tasks.exists(id)){
									logError('The task "${id}" already exists!');
								}
								else{
									//trace('task found: ${id}');
									tasks.set(id, [new Result(tk.lexeme, false)]);
								}
							}
							else if(section == ConfigSection.templates) { //In the templates section?
								if(templates.exists(id)){
									logError('The template "${id}" already exists!');
								}
								else {
									//Do we have a valid parameter array thus a vaild template declaration?
									if(parameterArray != null){
										if(inParameterList){
											logError("Expected ')'", tk);
											parameterArray = null;
										}
										else{
											var tmp = new Template(id, tk.lexeme, parameterArray);
											//trace('Found template: ${tmp.toString()}');
											parameterArray = null;
											templates.set(id, tmp);
											// trace('call: ${tmp.call(["input.file", "tak.out"])}');
										}
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
				case HRToken.leftBracket:
					//If we enter an array, make sure the task doesn't yet exist
					if(tasks.exists(id)){
						logError('The task "${id}" already exists!', tk);
					}
					else{ //create an empty array and set its id
						tasks.set(id,[]);
					}
				inArray++;
				case HRToken.rightBracket: inArray--;
				case HRToken.leftParen:
				if(section == ConfigSection.templates){
					if(previous().type == HRToken.identifier) {
						inParameterList = true; 
						parameterArray = [];
					}
				}
				else{
					if(previous().type == HRToken.identifier)
						logError('Unexpected template declaration ${previous().lexeme}(. Template declarations should go in the templates section!',tk);
					else
						logError('Unexpected "("', tk);
				}
				case HRToken.rightParen: inParameterList = false;
				// case HRToken.comma: 
				default:
			}
			tkIndex++;
		}

		if(section == ConfigSection.templates && inParameterList){
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
	function ExpandVariablesWithinTask(taskName:String){
	 	if(taskName == null || taskName == "") return;
		var taskSequence = tasks.get(taskName);
		if(taskSequence == null) return;

		trace('==== Expand Variables Within Task ====');

		//Go through all the sequences in this task
		trace('TaskName: $taskName');
		for(i in 0 ... taskSequence.length){
			if(taskSequence[i].isTaskRef) continue; //taskReferences don't get expanded
			trace('\tseq: $i => ${taskSequence[i].text}');
			Expand(taskSequence[i], variables);
		}
	}

	function ExpandVariablesWithinVariable(variableName:String){
		if(variableName == null || variableName == "" || !variables.exists(variableName) ) return;

		trace('==== Expand Variables Within $variableName ====');
		trace('Pre-expand: ${variables[variableName]}');
		variables[variableName] = varRegex.map(variables[variableName], function(reg:EReg){
			var vname = reg.matched(1);

			if(variables.exists(vname)){
				return variables[vname];
			}
			else
				return reg.matched(0);
		});
		trace('Post-expanded: ${variables[variableName]}');
	}

	function ExpandVariablesWithinTemplate(parametrizedTask:Template){
		if(parametrizedTask == null ) return;

		trace('==== Expand Variables Within Templates ====');

		parametrizedTask.text = varRegex.map(parametrizedTask.text, function(reg:EReg){
			var variableName = reg.matched(1);
			if(variables.exists(variableName)){
				return variables[variableName];
			}
			else
				return reg.matched(0);
		});
		//  trace('Task:${parametrizedTask.name} => ${parametrizedTask.text} ');
	}

	function ExpandTemplatesWithinTemplate(template:Template){
		if(template == null) return;

		trace('==== Expand Templates Within Templates ====');

		template.text = templatesRegex.map(template.text,
		function(reg:EReg){
				var templateName = reg.matched(1).substr(0, reg.matched(1).indexOf('('));
				var paramGlob = reg.matched(1).substr(templateName.length + 1);
				paramGlob = paramGlob.substr(0, paramGlob.length -1).trim();

				if(templates.exists(templateName)){
					//See if there are any parameters
					var params:Array<String>;
					
					//Are there some parameters to this template call?
					if(paramGlob.length > 0)
					 	params = paramGlob.split(",");
					else
						params = [];

					for(i in 0 ... params.length){
						params[i] = params[i].trim();
					}

					var tmpl = templates[templateName];
					var output:String = tmpl.call(params);

					//TODO: Make sure the correct number of parameters are given
					// if(tmpl.NumParams != params.length) 
					return output;
				}
				else{
					logError('Template: $templateName was not found!');
					return reg.matched(0);
				}
		}
		);
	}
	function ExpandTemplatesWithinTask(taskName:String){
	 	if(taskName == null || taskName == "") return;
		var taskSequence = tasks.get(taskName);
		if(taskSequence == null) return;

		trace('==== Expand Templates Within Task ====');

		for(i in 0 ... taskSequence.length){
			if(taskSequence[i].isTaskRef) continue; //taskReferences don't get expanded
			taskSequence[i].text = templatesRegex.map(taskSequence[i].text, 
			function (reg:EReg){
				var templateName = reg.matched(1).substr(0, reg.matched(1).indexOf('('));
				var paramGlob = reg.matched(1).substr(templateName.length + 1);
				paramGlob = paramGlob.substr(0, paramGlob.length -1).trim();

				trace('found template: ${templateName} params: ${paramGlob}');
				trace('full: ${templateName}(${reg.matched(1)})');

				if(templates.exists(templateName)){
					//See if there are any parameters
					var params:Array<String>;
					
					//Are there some parameters to this template call?
					if(paramGlob.length > 0)
					 	params = paramGlob.split(",");
					else
						params = [];

					for(i in 0 ... params.length){
						params[i] = params[i].trim();
					}

					var tmpl = templates[templateName];
					var output:String = tmpl.call(params);

					//TODO: Make sure the correct number of parameters are given
					// if(tmpl.NumParams != params.length) 
					return output;
				}
				else{
					logError('Template: $templateName was not found!');
					return reg.matched(0);
				}
			});
			// trace('=>:${taskSequence[i].text}');
		}
	}

	public function Expand(res:Result, replacements:Map<String,String>) {
		if(res == null || res.isTaskRef || replacements == null) return;
		// Sys.println('Before:${res.text}');
		res.text = Replace(res.text, varRegex, replacements);
		// Sys.println('After:${res.text}');
	}

	function Replace(text:String, regex:EReg, replacements:Map<String,String>): String {
		if(replacements == null){
			trace('replacements Map was empty');
			return text;
		}
		var newString = regex.map(text, function(regex){
			var varName = regex.matched(1);
			trace('Repl found variable: $varName');
			//See if we have any matching variables
			//If so, replace them with their replacement value
			//otherwise, return the original text
			for(key in replacements.keys()){
				if(key == varName) {
					trace('variable: $varName => ${replacements[key]}');
					return replacements[key];
				}
			}
			return regex.matched(0);
		});
		return newString;
	}

	//Returns an array of strings containing UNIQUE matches to the regex
	function GrabUniqueMatches(text:String, regex:EReg): Array<String>{
		var matches:Array<String> = [];
		if(text == null || regex == null) return matches;

		regex.map(text, function(re:EReg){
			var value = re.matched(1);
			if(matches.lastIndexOf(value) == -1)
				matches.push(value);
			return "";
		});
		return matches;
	}


	//Expands any command line args found within a task. By the time this is called
	//all variables should already be expanded and thus all task args should be found
	//
	public function ExpandTaskArgs(res:Result){
		if(res == null || res.isTaskRef ) return;

		res.text = taskArgsRegex.map(res.text, function(reg:EReg){
			var variableName = reg.matched(1);	
			var default_value = reg.matched(2); //if there is a default arg, grab it

			//It might be a reference to a task argument
			var argIndex = Std.parseInt(variableName);
			if(argIndex != null){
				argIndex--; //account for the fact that arrays are 0-based
				if(argIndex >= 0 && task_args.length > argIndex){
					return task_args[argIndex];
				}
				//If there was a default set, use it
				else if(default_value != null)
					//If the brackets are present for a default value [] the assume it is optional
					if(default_value.length == 0) return "";
					else return default_value;
				else{
					logError('Unable to find arg ${argIndex + 1}. Did you specify args on the cmd line?');
					return reg.matched(0);
				}
			}
			logError('Not a valid task cmd line argument!: ${variableName}');
			return reg.matched(0);
		});
		// trace('body: ${res.text}');
	}

	function ExpandTaskArgsWithinVariable(variableName:String){
		if(variableName == null || variableName == "" || !variables.exists(variableName) ) return;
		variables[variableName] = varRegex.map(variables[variableName], function(reg:EReg){
			var vname = reg.matched(1);

			if(variables.exists(vname)){
				return variables[vname];
			}
			else
				return reg.matched(0);
		});
		//trace('Variable:$variableName => $value => ${variables[variableName]}');
	}

	//Gets any task references embedded in this command
	public function GetEmbeddedTaskReferences(cmd:Result):Array<String> {
		if(cmd == null || cmd.isTaskRef) return null;

		var matches = GrabUniqueMatches(cmd.text, varRegex);
		
		//Get rid of any variables in this list and all
		//we should have left is Task references
		for (key in variables.keys()){
			if(matches.indexOf(key) != -1)
				matches.remove(key);
		}
		return matches;
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