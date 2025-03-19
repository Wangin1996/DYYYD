#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LivePhotoManager : NSObject

+ (void)createLivePhotoWithPhotoPath:(NSString *)photoPath
                          videoPath:(NSString *)videoPath
                         completion:(void(^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END