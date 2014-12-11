//
//  Xmas14.h
//
//  Created by Yousry Abdallah.
//  Copyright 2014 yousry.de. All rights reserved.

#import <Foundation/Foundation.h>
@class YARenderLoop, YAGameContext, YAImpGroup, YASoundCollector, YAOpenAL;

@interface Xmas14: NSObject {
    YARenderLoop* renderLoop;
    YASoundCollector* soundCollector;
    YAGameContext* gameContext;

    YAImpGroup *buttonStart, *buttonDifficulty, *buttonNumberOfPlayer;
    int sensorStart, sensorDifficulty, sensorNumPlayer;

}

- (id) initIn: (YARenderLoop*) loop;

- (void) setup;

@end