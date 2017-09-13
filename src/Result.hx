
class Result {
    
	public var text:String;
	public var isTaskRef(default,null):Bool;


	public function new(cmd:String, isTaskName:Bool){text = cmd; isTaskRef = isTaskName;}
	public function toString():String{return '${isTaskRef ? "TASK":"Cmd"}:${text}';	}
}