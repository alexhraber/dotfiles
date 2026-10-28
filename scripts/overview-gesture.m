#import "overview-gesture.h"
#include <dlfcn.h>
#include <stdatomic.h>
#include <os/lock.h>

// Apple's private trackpad ABI; declarations cross-checked against
// https://github.com/haonlabs/SwipeSwitcher/tree/main/Sources/CMultitouch
// Read touch centroids only. No images, touch history, logging or network use.
typedef struct {float x,y;} TouchPoint;
typedef struct {TouchPoint position,velocity;} TouchVector;
typedef struct {
    int32_t frame;double timestamp;int32_t identifier,state,fingerID,handID;
    TouchVector normalized;float size;int32_t unknown1;float angle,majorAxis,minorAxis;
    TouchVector absolute;int32_t unknown2,unknown3;float density;
} Touch;
_Static_assert(sizeof(Touch)==96,"Unexpected trackpad contact ABI");
typedef int (*TouchCallback)(void *,const Touch *,int32_t,double,int32_t);
typedef struct {BOOL armed,fired;double started;float x,y;int32_t ids[3];} Swipe;
static void (*registerFrame)(void *,TouchCallback),(*unregisterFrame)(void *,TouchCallback);
static int32_t (*startDevice)(void *,int32_t),(*stopDevice)(void *);
static CFArrayRef devices;
static Swipe swipes[16];
static void (^onSwipe)(BOOL);
static os_unfair_lock touchLock=OS_UNFAIR_LOCK_INIT;
static atomic_bool threeContacts;
static BOOL suppressMomentum;
static NSUInteger triggers,subscription;

// Exactly three stable contacts, dominant vertical movement, once per touch.
static int feed(Swipe *state,int count,float x,float y,double time,const int32_t ids[3]) {
    if(count==0){*state=(Swipe){0};return 0;}
    if(count!=3 || !isfinite(x) || !isfinite(y) || x<0 || x>1 || y<0 || y>1){state->armed=NO;return 0;}
    if(state->fired)return 0;
    if(!state->armed || memcmp(state->ids,ids,sizeof(state->ids))){
        *state=(Swipe){.armed=YES,.started=time,.x=x,.y=y};memcpy(state->ids,ids,sizeof(state->ids));return 0;
    }
    float dx=x-state->x,dy=y-state->y;double elapsed=time-state->started;
    if(elapsed<0 || elapsed>1.2 || (fabsf(dx)>.06 && fabsf(dx)>fabsf(dy)*1.3)){state->fired=YES;return 0;}
    if(elapsed<.025 || fabsf(dy)<.11 || fabsf(dy)<fabsf(dx)*1.6)return 0;
    state->fired=YES;return dy>0 ? 1 : -1;
}
static int contacts(void *device,const Touch *touches,int32_t count,double time,__unused int32_t frame) {
    if(count<0 || count>16)return 0;
    int active=0;float x=0,y=0;int32_t ids[3]={0};
    for(int i=0;i<count;i++)if(touches[i].state==3 || touches[i].state==4){
        if(active<3){x+=touches[i].normalized.position.x;y+=touches[i].normalized.position.y;ids[active]=touches[i].identifier;}active++;
    }
    for(int i=0;i<3;i++)for(int j=i+1;j<3;j++)if(ids[j]<ids[i]){int32_t swap=ids[i];ids[i]=ids[j];ids[j]=swap;}
    os_unfair_lock_lock(&touchLock);
    int result=0;
    for(CFIndex i=0;devices && i<MIN(16,CFArrayGetCount(devices));i++)if(CFArrayGetValueAtIndex(devices,i)==device){
        result=feed(&swipes[i],active,x/3,y/3,time,ids);break;
    }
    atomic_store(&threeContacts,active==3);
    if(result)triggers++;
    void (^action)(BOOL)=onSwipe;NSUInteger token=subscription;
    os_unfair_lock_unlock(&touchLock);
    if(result && action)dispatch_async(dispatch_get_main_queue(),^{os_unfair_lock_lock(&touchLock);BOOL current=token==subscription;os_unfair_lock_unlock(&touchLock);if(current)action(result>0);});
    return 0;
}
void DFOverviewGestureStop(void) {
    os_unfair_lock_lock(&touchLock);subscription++;CFArrayRef previous=devices;os_unfair_lock_unlock(&touchLock);if(!previous)return;
    for(CFIndex i=0;i<MIN(16,CFArrayGetCount(previous));i++){
        void *device=(void *)CFArrayGetValueAtIndex(previous,i);stopDevice(device);unregisterFrame(device,contacts);
    }
    os_unfair_lock_lock(&touchLock);devices=NULL;memset(swipes,0,sizeof(swipes));atomic_store(&threeContacts,false);os_unfair_lock_unlock(&touchLock);
    CFRelease(previous);
}
void DFOverviewGestureStart(void (^action)(BOOL)) {
    DFOverviewGestureStop();
    void *lib=dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_LAZY);
    if(!lib)return;
    CFArrayRef (*createList)(void)=dlsym(lib,"MTDeviceCreateList");
    registerFrame=dlsym(lib,"MTRegisterContactFrameCallback");unregisterFrame=dlsym(lib,"MTUnregisterContactFrameCallback");startDevice=dlsym(lib,"MTDeviceStart");stopDevice=dlsym(lib,"MTDeviceStop");
    if(!createList || !registerFrame || !unregisterFrame || !startDevice || !stopDevice)return;
    os_unfair_lock_lock(&touchLock);onSwipe=[action copy];devices=createList();os_unfair_lock_unlock(&touchLock);
    for(CFIndex i=0;devices && i<MIN(16,CFArrayGetCount(devices));i++){
        void *device=(void *)CFArrayGetValueAtIndex(devices,i);registerFrame(device,contacts);startDevice(device,0);
    }
}
BOOL DFOverviewGestureSuppressScroll(CGEventRef event) {
    if(atomic_load(&threeContacts)){suppressMomentum=YES;return YES;}
    if(suppressMomentum && CGEventGetIntegerValueField(event,kCGScrollWheelEventMomentumPhase))return YES;
    suppressMomentum=NO;return NO;
}
NSDictionary *DFOverviewGestureStatus(void) {
    os_unfair_lock_lock(&touchLock);NSDictionary *status=@{@"devices":@(devices ? MIN(16,CFArrayGetCount(devices)) : 0),@"recognized":@(triggers)};os_unfair_lock_unlock(&touchLock);return status;
}
int DFOverviewGestureSelfTest(void) {
    Swipe state={0};int32_t ids[]={1,2,3},changed[]={1,2,4};
    if(feed(&state,3,.5,.4,1,ids) || feed(&state,3,.52,.55,1.1,ids)!=1 || feed(&state,3,.52,.7,1.2,ids))return 1;
    feed(&state,0,0,0,2,ids);feed(&state,3,.5,.6,2,ids);if(feed(&state,3,.51,.4,2.1,ids)!=-1)return 1;
    feed(&state,0,0,0,3,ids);feed(&state,3,.5,.4,3,ids);if(feed(&state,3,.7,.45,3.1,ids) || feed(&state,3,.7,.7,3.2,ids))return 1;
    feed(&state,0,0,0,4,ids);feed(&state,3,.5,.4,4,ids);if(feed(&state,2,.5,.7,4.1,ids))return 1;
    feed(&state,0,0,0,5,ids);feed(&state,3,.5,.4,5,ids);if(feed(&state,4,.5,.7,5.1,ids))return 1;
    feed(&state,0,0,0,6,ids);feed(&state,3,.5,.4,6,ids);if(feed(&state,3,.5,.7,6.1,changed))return 1;
    if(feed(&state,3,NAN,.8,6.2,ids))return 1;
    puts("Overview gesture: three-finger up/down, stable contacts, axis lock, one-shot and other-finger rejection passed.");return 0;
}
