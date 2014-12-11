//
//  Xmas14.mm
//
//  Created by Yousry Abdallah.
//  Copyright 2014 yousry.de. All rights reserved.

#define GL_GLEXT_PROTOTYPES
#define GLCOREARB_PROTOTYPES
#import <GL/glcorearb.h>

#include <string>
#include <thread>
#include <mutex>
#import "CapCam.h"

#import "YATexture.h"
#import "YATexture+DynamicAdditions.h"
#import "YATextureManager.h"
#import "YAPreferences.h"
#import "HIDReader.h"
#import "YABasicAnimator.h"
#import "YABlockAnimator.h"
#import "YASpotLight.h"
#import "YAGouradLight.h"
#import "YAAvatar.h"
#import "YATransformator.h"
#import "YAMaterial.h"
#import "YAImpersonator.h"
#import "YAIngredient.h"
#import "YAPerspectiveProjectionInfo.h"
#import "YAQuaternion.h"
#import "YAVector3f.h"
#import "YAVector2f.h"
#import "YAVector2i.h"
#import "YATransformator.h"
#import "YARenderLoop.h"
#import "YALog.h"
#import "YADefenderUtils.h"
#import "YALightProbe.h"
#import "BlenderSceneImporter.h"


#import "Xmas14.h"

static const NSString* TAG = @"Xmas14";
static const double ZFAR = 100.0f;

using namespace std;
using namespace simpleVideo;

#define clamp(x,y,z) fminf(fmaxf(x,y),z)
#define async(cmds) dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ cmds });


@interface Xmas14 ()
{
    YADefenderUtils* defenderUtils;
    CapCam *capCam;
    __block void *camBuffer; 
    GLuint pboId;
    __block mutex mtx;

    BlenderSceneImporter *sceneDescription;       
}
@end


@implementation Xmas14 : NSObject

- (id) initIn: (YARenderLoop*) loop
{

    [YALog debug:TAG message:@"initIn"];
    self = [super init];

    if(self) {
        renderLoop = loop;
        defenderUtils = [[YADefenderUtils alloc] initIn: renderLoop];
        camBuffer = NULL;
    }

    return self;
}

- (void) dealloc
{
    if(capCam)
        delete(capCam);

    if(camBuffer)
        free(camBuffer);

    glDeleteBuffers(1, &pboId);

}

- (void) setup
{
    [YALog debug:TAG message:@"setup scene"];
    [YALog enableDebug];

    sceneDescription = [[BlenderSceneImporter alloc] initIn: renderLoop];
    [sceneDescription load:@"xmas14"];

    [self materialTweaks];
    [defenderUtils showHUD]; // 2D Setup: FPS, greetings 

    __block YAImpersonator* impBauble = [defenderUtils getImpForIngredient:@"Bauble"];
    impBauble.material.specIntensity = 0.5f;
    impBauble.material.roughnessIntensity = 0.25f;

    // camera movement / keaboard listener
    [self interactiveSetup: impBauble];

    // start webcam recording
    [self camWork: impBauble];

    // blender scenes have a small range
    renderLoop.transformer.projectionInfo.zNear = 0.1;
    renderLoop.transformer.projectionInfo.zFar = ZFAR;
    [[renderLoop transformer] recalcCam];


    // not available with ogl < 4
    renderLoop.deferred = NO;
    renderLoop.bloom = NO;

    // the background image 
    [renderLoop setSkyMap:@"xmas14"];
    renderLoop.showSkyMap = YES; 

    // calulating light information for 0/0/0 
    [renderLoop createLightProbe:@"xmas14Small" Position: [[YAVector3f alloc] init]];

    [renderLoop setTraceMouseMove:YES];

    // if deferred isn't activated texture alpha is used
    [renderLoop changeImpsSortOrder:SORT_IDENTITY_ALPHA];

    // start the rendering
    [renderLoop resetAnimators];
    [renderLoop setMultiSampling:YES];
    [renderLoop setActiveAnimation:true];
    renderLoop.drawScene = YES;
}


#pragma mark -
#pragma mark internal methods

- (void) materialTweaks
{
    __block YAImpersonator* imp = [defenderUtils getImpForIngredient:@"branch"];
    imp.material.specIntensity = 0.0f;
    imp.material.roughnessIntensity = 0.8f;
    [imp.material.phongAmbientReflectivity setValue: 4.0f];

    imp = [defenderUtils getImpForIngredient:@"BaubleThread"];
    imp.material.specIntensity = 0.8f;
    imp.material.roughnessIntensity = 0.6f;
    [imp.material.phongAmbientReflectivity setValue: 4.0f];

    imp = [defenderUtils getImpForIngredient:@"BaubleHead"];
    imp.material.specIntensity = 0.8f;
    imp.material.roughnessIntensity = 0.25f;
}


- (void) camWork: (YAImpersonator*) impBauble
{
        capCam = new CapCam();

    if(!capCam->init(NULL)) {
        [YALog debug:TAG message:@"Could not initialize capture device."];
        [YALog forceExit];
    }

    capCam->startStreaming();

    glGenBuffers(1, &pboId);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pboId);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 921600, 0, GL_STREAM_DRAW);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);

    __block int index = 0;
    __block int nextIndex = 0;
    __weak YAImpersonator* wImpBauble = impBauble;

    YATextureManager* tm = renderLoop.textureManager;
    __block YATexture *camTex = [tm createEmptyRectTexture: @"webCamTex" 
                                    Dimension: [[YAVector2i alloc] initVals: 640 : 480]];

    // capture 640 x 480 * 3
    camBuffer = malloc(921600);
    __block long remainFree= 0;

    // replace with try lock
    __block volatile bool inUpdate = false;
    __block volatile bool isNewCapture = false;


    [impBauble setSpecialMaterialize:^() {

        if(!inUpdate) {
            inUpdate = true;
            async(
                mtx.lock();
                remainFree = capCam->getCapture(camBuffer, 921600);
                mtx.unlock();
                assert(remainFree >= 0);
                inUpdate = false;
                isNewCapture = true;
            );
        }

        index = (index + 1) % 2;
        nextIndex = (index + 1) % 2;

        if(isNewCapture) {
            if(mtx.try_lock()) {
                // get the envtexture
                YALightProbe *lp = [renderLoop nearestLightProbe: wImpBauble.translation];

                // [camTex updateRectMemory: camBuffer];
                // or
                glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pboId);
                glBufferData(GL_PIXEL_UNPACK_BUFFER, 921600, camBuffer, GL_STREAM_DRAW);
                [camTex updateRectPixelBuffer: pboId];
                mtx.unlock();

                lp.auxiliaryTexture = camTex;
                isNewCapture = false;
            }
        }
    }];

}


- (void) interactiveSetup: (YAImpersonator*) impBauble
{
        __block YAVector2i* mouseVector = nil;
    __block YAVector2f* force = [[YAVector2f alloc] init];

    __block float actHead = 0;
    __block float actPitch = 0;

    __block float distance = [defenderUtils.avatar.position distanceTo: impBauble.translation];
    __block float actDistance = distance;

    const float defaultDistance = distance;
    const float reducedDistance = distance - 2.5f;

    YABlockAnimator* mausi = [renderLoop createBlockAnimator];
    mausi.asyncProcessing = YES;
    [mausi addListener:^(float spanPos, NSNumber* event, int message)
     {
        event_keyPressed ev = (event_keyPressed)event.intValue;

        if(ev == MOUSE_VECTOR) {
                mouseVector = [[YAVector2i alloc] initVals:(message >> 16) :message & 511];

                const float x = ((mouseVector.x / 512.0f) - 0.5f) * 0.25f;
                const float y = ((mouseVector.y / 512.0f) - 0.5f) * 0.25f;

                force.x = x;
                force.y = y;
        } else if(ev == SPACE) {
            if(message != 0) {
                distance = distance < defaultDistance ? defaultDistance : reducedDistance;
            }

        } else if(ev == MOUSE_DOWN) {
            impBauble.wireframe = !impBauble.wireframe;
        }

     }];

    YABlockAnimator* looki = [renderLoop createBlockAnimator];
    looki.asyncProcessing = false;

    [looki addListener:^(float spanPos, NSNumber* event, int message)
     {

        actHead += force.x;
        actPitch -= force.y;

        actPitch = clamp(actPitch, -5.0f, 5.0f);
        actHead = clamp(actHead, -25.0f, 25.0f);

        YAQuaternion* rot =  [[YAQuaternion alloc] initEulerDeg: actHead pitch: actPitch roll: 0.0];

        YAVector3f* pos = [[YAVector3f alloc] initZAxis];

        if(actDistance < distance)
            actDistance += 0.05f;
        else if(actDistance > distance)
            actDistance -= 0.05f;

        if(actDistance < reducedDistance)
            actDistance = reducedDistance;
        else if(actDistance > defaultDistance)
            actDistance = defaultDistance;

        [pos mulScalar: -actDistance];

        [[defenderUtils.avatar position] setVector: [rot rotate: pos]];
        [defenderUtils.avatar lookAt: [[YAVector3f alloc] initVals: 0 : 0.01 : 0 ]];


     }];
}

@end


#pragma mark -
#pragma mark utility functions