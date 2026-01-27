//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Foundation/Foundation.h>

typedef struct {
    float x, y;
} mtPoint;

typedef struct {
    mtPoint position;
    mtPoint velocity;
} mtReadout;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state; // 1 = finger down, 2 = finger up ?
    int unknown1;
    int unknown2;
    mtReadout normalized; // 0.0 - 1.0
    float size;
    int zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    mtReadout unknown3;
    int unknown4[2];
    float unknown5;
} mtTouch;

typedef void *MTDeviceRef;
typedef int (*MTContactCallbackFunction)(int, mtTouch *, int, double, int);

// Functions from MultitouchSupport.framework
extern MTDeviceRef MTDeviceCreateDefault();
extern CFArrayRef MTDeviceCreateList();
extern void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallbackFunction);
extern void MTDeviceStart(MTDeviceRef, int); // int is usually 0
extern void MTDeviceStop(MTDeviceRef);

