# HR
A very simple task runner written in Haxe

## Building

(Note: You will want to grab [Hix](https://github.com/bncastle/hix) which is my Haxe build tool for building.
Or, you can look in the HR.hx source file and tease out the compiler flags to feed the Haxe compiler.)

Open a command line in the project and type:

```hix HR.hx```

This will build HR as a cpp project, and the .exe will be found in ```bin``` directory.

## Usage

HR uses a ```tasks.json``` file located in the root of the directory where you want to run the tasks. Each
task is a JSON object containing a "name" property and a "cmds" array where command strings are specified.
Each task can be composed of just one command, multiple commands, or other tasks can also be specified as 
a command.An example ```tasks.json``` file is shown below:

```json

[
    {
        "name":"directory",
        "cmds":["dir"]
    },
    {
        "name":"dual",
        "cmds":[":directory","copy /?"]
    },
    {
        "name":"speak",
        "cmds":["!echo hello"]
    }
]

```

To run the "directory" task, you type:

```HR directory```

This will run all the commands contained within the directory task until a command returns non-zero (i.e. an error).
When a task is executed, each command will be printed to the console unless it is  prefixed by a "!". This
As previously mentioned, other tasks can also be executed as commands by prefacing them with a ":". The
"dual" command is an example of this as its first command is to run the "directory" task, then print the help on the
DOS copy command.

Available tasks can be listed by typing:

```HR -t ```

Well that's it for now. It's a pretty simple program mostly written as an exercise for me. More will come later.