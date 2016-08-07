# MYUtilities ##

## Objective-C utilities for Cocoa programming on Mac OS X and iPhone

by Jens Alfke <jens@mooseyard.com>

These are useful things I've built over the years and can't live without. 
All of this code is released under a BSD license; see the file `LICENSE.txt`.

(This Git repo is a continuation of the earlier Mercurial repo at [Bitbucket.org](https://bitbucket.org/snej/myutilities/src), which is by now quite out of date.)

The core parts are:

### CollectionUtils

A grab-bag of shortcuts for working with Foundation classes, mostly collections. Some of it has been made obsolete by the recent addition of Objective-C object literal support, but there's still a lot of useful stuff.

### Logging

Everyone seems to build their own logging utility; this is mine. The main nice feature is that you can log different categories of messages, and individually enable/disable output for each category by setting user defaults or command-line arguments. There's also a separate Warn() function that you can set a breakpoint on, which is itself a lifesaver during development.

### Test

My own somewhat oddball unit test system. I like being able to put unit tests in the same source file as the code they test. The tests run at launch time (if a command-line flag is set) not in a separate build phase. You can set dependencies between tests to get some control over the order in which they run. The output is IMHO easier to read than SenTest's.
