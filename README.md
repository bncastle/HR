# HR
A simple task runner written in Haxe.

A [VSCode extension](https://github.com/bncastle/hr-language-vscode-ext) is also available for coloring .hr files.

## Building

At the command line in the directory where this project is located, type:
` haxe build.hxml `
The .exe will be found in `bin` directory.

## Usage

HR looks for a special `config.hr` file located in the root of the directory where you want to run tasks.
If it can't find config.hr, then it looks for any file within the directory with a .hr extension. 

Each task is a key=value pair where the key identifies the task by name and the value is the command to be executed.
A task key also supports an array of task where each value is a task name preceeded by a `:` (see below example).

An optional variables section as shown below can be used to allow for more flexibility. To refer to a variable in a task,
enclose it between two ':'. ex: `:variableName:` where `variableName` is the name of the variable defined in the variables section
to which you want to refer (see below for examples). 

The output of tasks can also be used within the command of other
tasks by enclosing the name of the task in the same manner (examples are shown in the example below). Variable names and task names
are restricted to: 'A-Z', 'a-z' and '_'. Variable names cannot be surrounded by '_' (ex: _badName_). Variables with this naming
convention are reserved for system-defined variables.

There are some system-defined variables that are defined regardless of the hr config file that is being used. These variables can be used in 
any script. Below are all the currently-defined system variables:

`_cwd_ => outputs the current working directory`
`_hrd_ => outputs the location of the hr executable`

Tasks can be hidden from being listed by beginning their name with an underscore '_'. This will cause them to not appear in the available task listing, but they can still be executed. This provides a way to keep any "internal" tasks from being displayed in the listings.

A templates section as shown below can be used to implement a template that takes text parameters as input
and replaces their references with the text entered by the user. Note the parameter names in a template are refered to with a '$' preceding it. Templates can be called from tasks by preceeding them with '@' (this is subject to change). To call a template named copy(dir), you would use _copy(C:\yourDirHere)
An example `config.hr` file is shown below:

```php
    #comments look like this and are allowed outside sections, and between tasks and variables
    #There are two specific sections that are allowed in a config.hr file: variables and tasks
    #The use and variables section is optional and does not need to be defined if it is not needed
    --use
        #use other hr files here
        #files that don't have an absolute path will be searched from the path of the file in which they are
        #included first, then where the HR executable is located. Any duplicate use files are ignored
        default.hr
    --variables
        #This sets the name of our zip file
        zipName = TestPackage

    --tasks
        #Delete the zip file package if it exists
        deleteZip= if exist "@zipName.zip" (del :zipName:.zip)
        #Get the file version of the main .exe so we can add it to the end of the zipfile name
        #assuming of course that MyUtil.exe is a .NET executable
        fileVersion = powershell (Get-Item bin\Release\MyUtil.exe).VersionInfo.FileVersion
        #Use 7za.exe to archive the package (note the reference to the fileVersion task)
        zip = 7za.exe a -tzip :zipName:_:fileVersion:.zip README.txt Version.txt bin\Release\MyUtil.exe
        #Below is a task that runs several other tasks (note the task neames must all be preceeded by ':')
        buildZip = [:deleteZip, :zip]
        copytest = _copy(c:\utils\test)
    --templates
        copy(dir) = copy test.zip $dir/test.zip

```

## Command line arguments

HR also allows placing requirements for a command line argument within a variable or a task. The syntax for doing so looks like:

`@1 `

The number indicates which command line argument to grab. Note that the cmd line arguments start at 1 so
@1 looks for the 1st cmd line argument given AFTER the task name. An example task:

`print_name = echo hello @1!`

When executed, this task will expect a single command line argument. If it does not find one, it will print an error explaining what it was looking for and exit. To call this task correctly, you would type:

`hr.exe print_name Jeff`

This would then produce the output:

`hello Jeff!`

Default command line args can also be provided:

`print_name = echo hello @1[Judy]!`

The default value of "Judy" is now inserted if there is not an argument available.

`hr.exe print_name`

This would then produce the output:

`hello Judy!`

In addition, you can specify that the argument is optional by providing empty brackets:

`print_name = echo hello @1[]!`

Running the above with no argument would then produce the output:

`hello !`

Note that there are possible issues when using cmd line argument references in tasks that refer to each other, so be careful!

## Building HR

To run the "buildZip" task, you type:

`HR buildZip`

This will run the `buildZip` task. This task happens to be an array which means it can only contain other 
tasks, and each of those tasks will be run in the order that they appear within the array. Tasks can, as 
descibed above, refer to the output of another task, but circular references are not allowed.

Available tasks can be listed by typing:

`HR -t `

Verbose mode can be enabled by using the `-v` switch:

`HR -v buildZip`

Verbose mode will print the command itself to the console as well as the output of each command.

Alternate config files can exist in the same directory and can be used by specifying its name before the desired task:

`HR myConfig.hr rakeLeaves`

