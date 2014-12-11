#import <Foundation/Foundation.h>

#import "Xmas14.h"

#import "YATexture.h"
#import "YARenderLoop.h"

int main (int argc, const char * argv[])
{

	@autoreleasepool { // dynamic stuff not  replaced with c++ rt

		NSLog(@"Application Startup");

		YARenderLoop* renderLoop = [[YARenderLoop alloc] init];
		[renderLoop prepareOpenGL];
		[renderLoop setUpMetaWorld];

		Xmas14* scene = [[Xmas14 alloc] initIn: renderLoop];
		[scene setup];

		// don't need to update/work on textures (free space)
		[YATexture cleanup];

		NSLog(@"start loop");
		[renderLoop doLoop];
	}

	return 0;
}
