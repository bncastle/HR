import sys.FileSystem;
import sys.io.File;
import haxe.Json;

// @author Bryan Castleberry
//
//The comments below are meant to utilize my Hix utility to compile/run
//without needing a build.hxml or command line options. Hix can be found here:
//https://github.com/bncastle/hix
//
//::hix -main HR --no-traces -dce full -cpp bin
//::hix:neko -main HR --no-traces -dce full -neko hr.n

//This lets Haxe know what structure we expect in our JSON task file
//
typedef Task = 
{
	var name: String;
	var cmds: Array<String>;
}

//typedef Cfg =
//{
	//var shell:String;
	//var tasks: Array<Task> ;
//}

class HR
{
	static inline var VERSION = "0.2";
	static inline var CFG_FILE = "hr.json";
	static inline var ERR_TASK_NO_FOUND = -1025;
	var tasks:Array<Task>;
	
	static function main(): Int
	{
		Sys.println('HR Version $VERSION): A simple Task runner.');
		Sys.println("Copyright 2016 Pixelbyte Studios");
		
		//Note this: We want the config file in the directory where we were invoked!
		var cfgFile:String = Sys.getCwd() + CFG_FILE;
		
		if (Sys.args().length < 1)
		{
			Sys.println("Usage: HR.exe <task_name>");
			Sys.println("HR.exe -t (prints a list of valid tasks)");
			
			if (!HR.CheckForConfigFile(cfgFile))
			{
				Sys.println('Make a $CFG_FILE file and put it in your project directory.');
				Sys.println("EX: [ {\"name\":\"task1\",\"cmds\": [\"cmd1\", \"cmd2\"] } ]");
				Sys.println("You can a task by specifying its name");
				Sys.println("If you want to run a task within a task, precede the task label by ':'");
				Sys.println("If you don't want task's command to be displayed when its run, add '!' to the beginning of the command");
				Sys.println("HR.exe task1");
			}
			return -1;
		}
		
		var h = new HR();
		if (!h.ParseConfig(cfgFile))
		{
			return -1;
		}
		
		if (Sys.args()[0] == "-t")
		{
			h.PrintAvailableTasks();
			return -1;
		}

		var taskName:String = Sys.args()[0];
		var retCode:Int = h.RunTask(taskName);
		if (retCode == ERR_TASK_NO_FOUND)
		{
			Sys.println("Task: " + taskName + " not found!");
			return -1;
		}
		else if ( retCode != 0)
		{
			Sys.println("Error running task: " + taskName);
			return -1;
		}
		
		return retCode;
	}
	
	public function new() { }
	
	function ParseConfig(cfgFile:String): Bool
	{	
		if (!HR.CheckForConfigFile(cfgFile)) return false;
		
		//Grab all the text from the file
		var text = File.getContent(cfgFile);
		
		//Parse the JSON
		tasks = Json.parse(text);

		if (tasks.length < 1)
		{
			Sys.println("No tasks found in " + CFG_FILE);
			return false;
		}
		
		//for (i in 0 ... tasks.length ) 
		//{
			//if (tasks[i].name == "")
				//tasks.splice(i, 1);
		//}

		return true;
	}

	function RunTask(name: String):Int
	{
		for	(t in tasks)
		{
			if (name.toLowerCase() == t.name.toLowerCase())
			{
				if (t.cmds.length == 0)
				{
					Sys.println("No commands found for task: " + name);
					return -1;
				}
				else
				{
					for (cmd in t.cmds)
					{
						//See if the command is itself a task. If it is, run it
						if(cmd.charAt(0) == ":")
						{
							var retcode:Int = RunTask(cmd.substr(1));
							if (retcode != 0) return retcode;
						}
						else
						{
							//If there is a ! at the beginning, that means Dont print the command when running it
							if(cmd.charAt(0)!="!")
								Sys.println(cmd);
							else
								cmd = cmd.substr(1); //remove the "!" from the command								
							var retcode:Int = Sys.command(cmd);
							if (retcode != 0) return retcode;
						}
					}
					return 0;
				}
			}
		}
		return ERR_TASK_NO_FOUND;
	}

	function PrintAvailableTasks()
	{
		Sys.println("Available Tasks:");
		for	(t in tasks)
		{
			Sys.println(t.name);
		}
	}
	
	//function IsTask(name:String)
	//{
	//	for (t in tasks) 
	//	{
	//		if (name.toLowerCase() == t.name.toLowerCase()) return true;
	//	}
	//	return false;
	//}
	
	static function CheckForConfigFile(cfgFile:String): Bool
	{
		//Check for a valid config file
		if (!FileSystem.exists(cfgFile))
		{
			Sys.print("Config file " + cfgFile + " doesn't exist.");
			return false;
		}
		return true;
	}
}