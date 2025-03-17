#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LivePhotoConverter : NSObject

/// 初始化转换器
/// @param videoPath 原始视频路径
- (instancetype)initWithVideoPath:(NSString *)videoPath;

/// 转换并生成Live Photo文件
/// @param outputPath 输出MOV文件路径
/// @param identifier 唯一标识符（需与图片一致）
/// @param completion 完成回调
- (void)convertToLivePhotoWithOutputPath:(NSString *)outputPath
                             identifier:(NSString *)identifier
                             completion:(void(^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END