# Soduto

> [!IMPORTANT]  
> Original project from this repository is not under development anymore.
> You may want to check out forked versions instead.
>
> One of the forks which seems to be actively developed is at https://github.com/sannidhyaroy/Soduto.
> I do not know the developer(s) of that fork, nor do I encourage to use their version - Soduto may access a lot of your private data,
> so use your own judgement whether to trust the developer(s).

## What is it?

Soduto is a KDEConnect compatible application for macOS. It allows better integration between your phones, desktops and tablets. 
For more information take a look at [soduto.com](https://www.soduto.com)

## Installation

Soduto application can be downloaded from [soduto.com](https://www.soduto.com). To install, open the downloaded .dmg file and drag 
Soduto.app onto Applications folder.

There is also a (unofficial) Homebrew formulae, that can install Soduto with such command:

```bash
brew install --cask soduto
```

## Building

* Install [Homebrew](https://brew.sh/):

    `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
    
* Add Homebrew to your PATH in `~/.profile`:
    
    ```
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.profile
    eval "$(/opt/homebrew/bin/brew shellenv)"
    ```

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
