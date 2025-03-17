#import "LivePhotoConverter.h"
#import <CoreMedia/CoreMedia.h>

@implementation LivePhotoConverter {
    NSString *_videoPath;
    AVAsset *_videoAsset;
}

- (instancetype)initWithVideoPath:(NSString *)videoPath {
    if (self = [super init]) {
        _videoPath = videoPath;
        _videoAsset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    }
    return self;
}

#pragma mark - 核心转换方法
- (void)convertToLivePhotoWithOutputPath:(NSString *)outputPath
                             identifier:(NSString *)identifier
                             completion:(void(^)(BOOL success, NSError *_Nullable error))completion 
{
    NSError *error;
    NSURL *outputURL = [NSURL fileURLWithPath:outputPath];
    
    // 初始化写入器
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:outputURL
                                                    fileType:AVFileTypeQuickTimeMovie
                                                       error:&error];
    if (!writer) {
        completion(NO, error);
        return;
    }
    
    // 添加必要元数据
    writer.metadata = @[
        [self metadataItemForIdentifier:identifier],
        [self stillImageTimeMetadataItem]
    ];
    
    // 配置视频轨道
    AVAssetTrack *videoTrack = [[_videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) {
        completion(NO, [self errorWithMessage:@"未找到视频轨道" code:1001]);
        return;
    }
    
    AVAssetWriterInput *videoInput = [self configureVideoInputForTrack:videoTrack];
    if (![writer canAddInput:videoInput]) {
        completion(NO, [self errorWithMessage:@"无法添加视频输入" code:1002]);
        return;
    }
    [writer addInput:videoInput];
    
    // 开始写入流程
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    
    // 初始化读取器
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:_videoAsset error:&error];
    if (!reader) {
        [writer cancelWriting];
        completion(NO, error);
        return;
    }
    
    // 配置读取输出
    NSDictionary *outputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
    AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack
                                                                                       outputSettings:outputSettings];
    [reader addOutput:videoOutput];
    
    if (![reader startReading]) {
        [writer cancelWriting];
        completion(NO, reader.error);
        return;
    }
    
    // 数据处理队列
    dispatch_queue_t processingQueue = dispatch_queue_create("livephoto.processing.queue", DISPATCH_QUEUE_SERIAL);
    
    [videoInput requestMediaDataWhenReadyOnQueue:processingQueue usingBlock:^{
        while ([videoInput isReadyForMoreMediaData]) {
            CMSampleBufferRef sampleBuffer = [videoOutput copyNextSampleBuffer];
            
            if (sampleBuffer) {
                if (reader.status == AVAssetReaderStatusReading) {
                    [videoInput appendSampleBuffer:sampleBuffer];
                }
                CFRelease(sampleBuffer);
            } else {
                [videoInput markAsFinished];
                
                if (reader.status == AVAssetReaderStatusCompleted) {
                    [writer finishWritingWithCompletionHandler:^{
                        completion(writer.status == AVAssetWriterStatusCompleted, writer.error);
                    }];
                } else {
                    [writer cancelWriting];
                    completion(NO, reader.error);
                }
                break;
            }
        }
    }];
}

#pragma mark - 辅助方法
- (AVMetadataItem *)metadataItemForIdentifier:(NSString *)identifier {
    AVMutableMetadataItem *item = [[AVMutableMetadataItem alloc] init];
    item.identifier = AVMetadataIdentifierQuickTimeMetadataContentIdentifier;
    item.value = identifier;
    item.dataType = (__bridge NSString *)kCMMetadataDataType_UTF8;
    return [item copy];
}

- (AVMetadataItem *)stillImageTimeMetadataItem {
    AVMutableMetadataItem *item = [[AVMutableMetadataItem alloc] init];
    item.identifier = AVMetadataIdentifierQuickTimeMetadataStillImageTime;
    item.value = @0;
    item.dataType = (__bridge NSString *)kCMMetadataBaseDataType_SInt8;
    return [item copy];
}

- (AVAssetWriterInput *)configureVideoInputForTrack:(AVAssetTrack *)track {
    NSDictionary *settings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(track.naturalSize.width),
        AVVideoHeightKey: @(track.naturalSize.height)
    };
    
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                  outputSettings:settings];
    input.transform = track.preferredTransform;
    input.expectsMediaDataInRealTime = YES;
    return input;
}

- (NSError *)errorWithMessage:(NSString *)message code:(NSInteger)code {
    return [NSError errorWithDomain:@"LivePhotoConverter" 
                               code:code 
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
