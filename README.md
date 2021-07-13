# Soduto

## What is it?

Soduto is a KDEConnect compatible application for macOS. It allows better integration between your phones, desktops and tablets. 
For more information take a look at [soduto.com](https://www.soduto.com)

## Building

* Install [Homebrew](https://brew.sh/):

    `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

* Install `libtool` and `automake` using Homebrew:

    `brew install libtool automake`

* Checkout Soduto repository with dependent submodules: 

    `git clone --recurse-submodules https://github.com/soduto/Soduto.git Soduto`

* Open project `Soduto.xcodeproj` with XCode
* Build target `Soduto`

## Debugging

* To see logged messages of Release build of Soduto:
    * Open `Console.app`
    * On Action menu select "Include Debug Messages"
    * In Search field enter "process:Soduto category:CleanroomLogger"

* To switch logging level in `Terminal.app` run command (with `<level>` being an integer between 1 and 5, 1 being the most verbose and 5 - the least):

    `defaults write com.soduto.Soduto com.soduto.logLevel -int <level>`
    
    It is highly recommended to enable verbose logging levels only during debugging as sensitive data may be logged in plain text (like passwords copied into a clipboard)
