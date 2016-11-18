# HR
A simple task runner written in Haxe

## Building

At the command line in the directory where this project is located, type:
` haxe build.hxml `
The .exe will be found in `bin` directory.

## Usage

HR uses a special `config.hr` file located in the root of the directory where you want to run the tasks. Each
task is a key=value pair where the key identifies the task by name and the value is the command to be executed.
A task key also supports an array of task where each value is a task name preceeded by a `:` (see below example).
An optional variables section as shown below can be used to allow for more flexibility. To refer to a variable in a task,
it must be enclosed in `|@variableName|` where `variableName` is the name of the variable defined in the variables section
to which you want to refer (see below for examples). The output of tasks can also be used within the command of other
tasks by enclosing the name of the task in the same manner (examples are shown in the example below). 
An example `config.hr` file is shown below:

```php
    #comments look like this and are allowed outside sections, and between tasks and variables
    #There are two specific sections that are allowed in a config.hr file: variables and tasks
    #The variables section is optional and does not need to be defined if it is not needed
    variables{
        #This sets the name of our zip file
        zipName = TestPackage
    }

    tasks{
        #Delete the zip file package if it exists
        delete-zip= if exist "|@zipName|.zip" (del @zipName|.zip)
        #Get the file version of the main .exe so we can add it to the end of the zipfile name
        #assuming of course that MyUtil.exe is a .NET executable
        file-version = powershell (Get-Item bin\Release\MyUtil.exe).VersionInfo.FileVersion
        #Use 7za.exe to archive the package (note the reference to the file-version task)
        zip = 7za.exe a -tzip |@zipName|_|@file-version|.zip README.txt Version.txt bin\Release\MyUtil.exe
        #Below is a task that runs several other tasks (note the task neames must all be preceeded by ':')
        build-zip = [:delete-zip, :zip]
    }


```

To run the "build-zip" task, you type:

`HR build-zip`

This will run the `build-zip` task. This task happens to be an array which means it can only contain other 
tasks, and each of those tasks will be run in the order that they appear within the array. Tasks can, as 
descibed above, refer to the output of another task, but circular references are not allowed.

Available tasks can be listed by typing:

`HR -t `

Verbose mode can be enabled by using the `-t` switch:

`HR -v build-zip`

Verbose mode will print the command itself to the console as well as the output of each command.
