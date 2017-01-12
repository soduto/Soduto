//
//  AppDelegate.m
//  SodutoLauncher
//
//  Created by Giedrius Stanevičius on 2017-01-11.
//  Copyright © 2017 Soduto. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    NSArray *pathComponents = [[[NSBundle mainBundle] bundlePath] pathComponents];
    pathComponents = [pathComponents subarrayWithRange:NSMakeRange(0, [pathComponents count] - 4)];
    NSString *path = [NSString pathWithComponents:pathComponents];
    [[NSWorkspace sharedWorkspace] launchApplication:path];

}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


@end
