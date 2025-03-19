#import "LivePhotoManager.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h> 

@implementation LivePhotoManager {
    dispatch_group_t _processingGroup;
    AVAssetWriter *_assetWriter;
    AVAssetReader *_assetReader;
}

+ (void)createLivePhotoWithPhotoPath:(NSString *)photoPath
                          videoPath:(NSString *)videoPath
                         completion:(void(^)(BOOL success, NSError *_Nullable error))completion
{
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            if (completion) completion(NO, [NSError errorWithDomain:@"PhotoAccess" code:403 userInfo:@{NSLocalizedDescriptionKey : @"无相册访问权限"}]);
            return;
        }
        
        // 生成唯一标识符
        NSString *uuidString = [[NSUUID UUID] UUIDString];
        
        // 处理媒体文件
        NSString *processedPhoto = [self processPhoto:photoPath identifier:uuidString];
        NSString *processedVideo = [self processVideo:videoPath identifier:uuidString];
        
        if (!processedPhoto || !processedVideo) {
            if (completion) completion(NO, [NSError errorWithDomain:@"Processing" code:500 userInfo:@{NSLocalizedDescriptionKey : @"媒体文件处理失败"}]);
            return;
        }
        
        // 保存到系统相册
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
            [creationRequest addResourceWithType:PHAssetResourceTypePhoto
                                        fileURL:[NSURL fileURLWithPath:processedPhoto]
                                       options:nil];
            [creationRequest addResourceWithType:PHAssetResourceTypePairedVideo
                                        fileURL:[NSURL fileURLWithPath:processedVideo]
                                       options:nil];
        } completionHandler:^(BOOL success, NSError *_Nullable error) {
            [[NSFileManager defaultManager] removeItemAtPath:processedPhoto error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:processedVideo error:nil];
            
            if (completion) completion(success, error);
        }];
    }];
}

#pragma mark - 核心处理方法
+ (NSString *)processPhoto:(NSString *)photoPath identifier:(NSString *)identifier {
    NSData *photoData = [NSData dataWithContentsOfFile:photoPath];
    if (!photoData) return nil;
    
    // 添加元数据
    NSDictionary *metadata = @{(NSString *)kCGImagePropertyMakerAppleDictionary : @{@"17" : identifier}};
 CGImageDestinationRef destination = CGImageDestinationCreateWithData((CFMutableDataRef)photoData.mutableCopy, UTTypeJPEG, 1, NULL);
    CGImageDestinationAddImage(destination, [UIImage imageWithData:photoData].CGImage, (CFDictionaryRef)metadata);
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
    
    // 保存临时文件
    NSString *outputPath = [self tempFilePathForExtension:@"jpg"];
    [photoData writeToFile:outputPath atomically:YES];
    return outputPath;
}

+ (NSString *)processVideo:(NSString *)videoPath identifier:(NSString *)identifier {
    NSError *error;
    AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    
    // 初始化读写器
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:[self tempFilePathForExtension:@"mov"]]
                                                   fileType:AVFileTypeQuickTimeMovie
                                                      error:&error];
    
    // 配置元数据
    NSMutableArray<AVMetadataItem *> *metadataItems = [NSMutableArray array];
    [metadataItems addObject:[self metadataItemForIdentifier:identifier]];
    writer.metadata = metadataItems;
    
    // 配置视频轨道
    [asset.tracks enumerateObjectsUsingBlock:^(AVAssetTrack *track, NSUInteger idx, BOOL *stop) {
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
        AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:track.mediaType outputSettings:nil];
        
        if ([reader canAddOutput:output] && [writer canAddInput:input]) {
            [reader addOutput:output];
            [writer addInput:input];
        }
    }];
    
    // 添加静态时间元数据
    AVAssetWriterInput *timedInput = [self timedMetadataInput];
    AVAssetWriterInputMetadataAdaptor *adaptor = [AVAssetWriterInputMetadataAdaptor assetWriterInputMetadataAdaptorWithAssetWriterInput:timedInput];
    [writer addInput:timedInput];
    
    // 开始处理
    [writer startWriting];
    [reader startReading];
    [writer startSessionAtSourceTime:kCMTimeZero];
    
    // 写入时间元数据
    CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMake(1, 1000));
    AVTimedMetadataGroup *metadataGroup = [[AVTimedMetadataGroup alloc] initWithItems:@[[self timedMetadataItem]] timeRange:timeRange];
    [adaptor appendTimedMetadataGroup:metadataGroup];
    
    // 处理样本数据
    dispatch_group_t processGroup = dispatch_group_create();
    [writer.inputs enumerateObjectsUsingBlock:^(AVAssetWriterInput *input, NSUInteger idx, BOOL *stop) {
        dispatch_group_enter(processGroup);
        [self processInput:input fromOutput:reader.outputs[idx] completion:^{
            dispatch_group_leave(processGroup);
        }];
    }];
    
    // 完成处理
    dispatch_group_notify(processGroup, dispatch_get_main_queue(), ^{
        [reader cancelReading];
        [writer finishWritingWithCompletionHandler:^{}];
    });
    
    return writer.outputURL.path;
}

#pragma mark - 工具方法
+ (NSString *)tempFilePathForExtension:(NSString *)ext {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [NSUUID UUID].UUIDString, ext]];
}

+ (AVMetadataItem *)metadataItemForIdentifier:(NSString *)identifier {
    AVMutableMetadataItem *item = [AVMutableMetadataItem new];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = AVMetadataQuickTimeMetadataKeyContentIdentifier;
    item.value = identifier;
    return item;
}

+ (AVAssetWriterInput *)timedMetadataInput {
    NSDictionary *spec = @{
        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier : @"mdta/com.apple.quicktime.still-image-time",
        (NSString *)kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType : (NSString *)kCMMetadataBaseDataType_SInt8
    };
    
    CMFormatDescriptionRef desc;
    CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, (__bridge CFArrayRef)@[spec], &desc);
    
    return [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeMetadata
                                              outputSettings:nil
                                            sourceFormatHint:desc];
}

+ (AVMetadataItem *)timedMetadataItem {
    AVMutableMetadataItem *item = [AVMutableMetadataItem new];
    item.keySpace = AVMetadataKeySpaceQuickTimeMetadata;
    item.key = @"com.apple.quicktime.still-image-time";
    item.value = @(-1);
    item.dataType = (NSString *)kCMMetadataBaseDataType_SInt8;
    return item;
}

+ (void)processInput:(AVAssetWriterInput *)input 
         fromOutput:(AVAssetReaderOutput *)output 
         completion:(void(^)(void))completion
{
    dispatch_queue_t queue = dispatch_queue_create("com.livephoto.process", DISPATCH_QUEUE_SERIAL);
    [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
        while (input.isReadyForMoreMediaData) {
            CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
            if (sampleBuffer) {
                [input appendSampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            } else {
                [input markAsFinished];
                if (completion) completion();
                break;
            }
        }
    }];
}

@end
