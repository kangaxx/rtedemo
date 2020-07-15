//
//  RoomViewController.m
//  OpenLiveVoice
//
//  Created by CavanSu on 2017/9/18.
//  Copyright © 2017 Agora. All rights reserved.
//

#import <AgoraRtcKit/AgoraRtcEngineKit.h>
#import "RoomViewController.h"
#import "KeyCenter.h"
#import "InfoCell.h"
#import "InfoModel.h"
#import "AgoraMediaDataPlugin.h"
#import "PFAudio.h"
@interface RoomViewController () <UITableViewDataSource, UITableViewDelegate, AgoraRtcEngineDelegate,AgoraAudioDataPluginDelegate>
@property (weak, nonatomic) IBOutlet UILabel *roomNameLabel;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIButton *roleButton;
@property (weak, nonatomic) IBOutlet UIButton *speakerButton;
@property (nonatomic, strong) NSMutableArray *infoArray;
@property (nonatomic, strong) AgoraRtcEngineKit *agoraKit;
@property (nonatomic, strong) AgoraMediaDataPlugin *agoraMediaDataPlugin;
@property (assign, nonatomic) BOOL needWritePCM;
@property (assign, nonatomic) BOOL isStartAudioMixing;
@property (assign, nonatomic) BOOL isPlayEffect;
@property (assign, nonatomic) BOOL isPublishMic;
@property (assign, nonatomic) BOOL isMuteRecordingSignal;
@end

static NSString *cellID = @"infoID";

@implementation RoomViewController
FILE *fp_OnRecord_pcm = NULL;
FILE *fp_OnMixed_pcm = NULL;
FILE *fp_PlayBack_pcm = NULL;
FILE *fp_PlayBackBeforeMixing_pcm = NULL;
NSString *audioRawDataDir = @"audioRawDataDir";
typedef NS_ENUM(int, AgoraSDKRawDataType) {
    AgoraSDKRawDataType_OnRecord,
    AgoraSDKRawDataType_OnMixed,
    AgoraSDKRawDataType_PlayBack,
    AgoraSDKRawDataType_PlayBackBeforeMixing
};


- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateViews];
    [self loadAgoraKit];
    self.needWritePCM = YES;
    self.isStartAudioMixing = NO;
    self.isMuteRecordingSignal = NO;
    self.isPublishMic = YES;
    self.isPlayEffect = NO;
}

#pragma mark- setupViews
- (void)updateViews {
    self.roomNameLabel.text = self.channelName;
//    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.backgroundColor = [UIColor blackColor];
}

#pragma mark- initAgoraKit
- (void)loadAgoraKit {

    AgoraRtcEngineConfig * config = [[AgoraRtcEngineConfig alloc] init] ;
    config.appId = [KeyCenter AppId];
    config.channelProfile = AgoraChannelProfileLiveBroadcasting;
    config.audioScenario = AgoraAudioScenarioGameStreaming;
    config.areaCode = AgoraAreaCodeTypeGlobal;
    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithConfig:config delegate:self];
    
//    self.agoraKit = [AgoraRtcEngineKit sharedEngineWithAppId:[KeyCenter AppId] delegate:self];
//    [self.agoraKit setChannelProfile:AgoraChannelProfileLiveBroadcasting];
    
    AgoraClientRole role;
    
    switch (self.roleType) {
        case RoleTypeBroadcaster:
            role = AgoraClientRoleBroadcaster;
            self.roleButton.selected = NO;
            [self appendInfoToTableViewWithInfo:@"Set Broadcaster"];
            break;
            
        case RoleTypeAudience:
            role = AgoraClientRoleAudience;
            self.roleButton.selected = YES;
            [self appendInfoToTableViewWithInfo:@"Set Audience"];
            break;
    }
    [self.agoraKit setClientRole:role];
//    [self.agoraKit setAudioProfile:AgoraAudioProfileMusicStandardStereo scenario:AgoraAudioScenarioGameStreaming];
//    [self.agoraKit setAudioProfile:AgoraAudioProfileMusicStandardStereo scenario:AgoraAudioScenarioGameStreaming];
//    [self.agoraKit setAudioProfile:AgoraAudioProfileMusicStandardStereo];
//    [self.agoraKit setEnableSpeakerphone:YES];
    [self.agoraKit setDefaultAudioRouteToSpeakerphone:YES];
//    [self.agoraKit setMixedAudioFrameParametersWithSampleRate:44100 channel:1 samplesPerCall:4410];
    [self.agoraKit setMixedAudioFrameParametersWithSampleRate:48000 channel:2 samplesPerCall:480];
    [self.agoraKit setRecordingAudioFrameParametersWithSampleRate:48000 channel:2 mode:0 samplesPerCall:480];
    
    self.agoraMediaDataPlugin = [AgoraMediaDataPlugin mediaDataPluginWithAgoraKit:self.agoraKit];
    
    [self.agoraKit enableAudioVolumeIndication:200 smooth:3];
    [self.agoraKit joinChannelByToken:nil channelId:self.channelName info:nil uid:0 joinSuccess:nil];
}

#pragma mark- Append info to tableView to display
- (void)appendInfoToTableViewWithInfo:(NSString *)infoStr {
    InfoModel *model = [InfoModel modelWithInfoStr:infoStr];
    [self.infoArray insertObject:model atIndex:0];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationLeft];
}

#pragma mark- Click buttons
- (IBAction)clickMuteButton:(UIButton *)sender {
    [self.agoraKit muteLocalAudioStream:sender.selected];
}

- (IBAction)clickHungUpButton:(UIButton *)sender {
    __weak typeof(RoomViewController) *weakself = self;
    [self.agoraKit leaveChannel:^(AgoraChannelStats * _Nonnull stat) {
        [weakself dismissViewControllerAnimated:YES completion:nil];
    }];
    [self stopRecordPCM:AgoraSDKRawDataType_OnRecord];
}

- (IBAction)clickSpeakerButton:(UIButton *)sender {
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        sender.selected = NO;
    }
    else {
        [self.agoraKit setEnableSpeakerphone:!sender.selected];
    }
}

- (IBAction)clickRoleButton:(UIButton *)sender {
    AgoraClientRole role = sender.selected ? AgoraClientRoleAudience : AgoraClientRoleBroadcaster;
    if (role == AgoraClientRoleBroadcaster && self.speakerButton.selected) {
        self.speakerButton.selected = NO;
    }
    [self.agoraKit setClientRole:role];
}

- (IBAction)clickPlayEffect:(UIButton *)sender {
    NSString *path = [[NSBundle mainBundle]pathForResource:@"testeffect" ofType:@"mp3"];
    [self.agoraKit playEffect:arc4random_uniform(255) filePath:path loopCount:1 pitch:1 pan:1 gain:80 publish:YES];
}

- (IBAction)clickStartAudioMixing:(UIButton *)sender {
    self.isStartAudioMixing = !self.isStartAudioMixing;
    if(self.isStartAudioMixing) {
        NSString *path = [[NSBundle mainBundle]pathForResource:@"audio_leftbigrightsmall" ofType:@"wav"];
        [self.agoraKit startAudioMixing:path loopback:NO replace:NO cycle:1];
        [sender setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    } else {
        [self.agoraKit stopAudioMixing];
        [sender setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }
}

- (IBAction)publishMic:(UIButton *)sender {
    self.isPublishMic = !self.isPublishMic;
    if(self.isPublishMic) {
         //大重构新特性，默认发布麦克风流 + 背景音乐
            AgoraRtcChannelMediaOptions* options1 = [[AgoraRtcChannelMediaOptions alloc] init];
            options1.publishAudioTrack = YES;
            options1.channelProfile = AgoraChannelProfileLiveBroadcasting;
            options1.clientRoleType = AgoraClientRoleBroadcaster;
            options1.publishMediaPlayerAudioTrack = YES;
        //    options1.publishCustomAudioTrack = YES;
            [self.agoraKit updateChannelWithMediaOptions:options1];
         [sender setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    } else {
         //大重构新特性，不发布麦克风流，但是发布背景音乐
            AgoraRtcChannelMediaOptions* options1 = [[AgoraRtcChannelMediaOptions alloc] init];
            options1.publishAudioTrack = NO;
            options1.channelProfile = AgoraChannelProfileLiveBroadcasting;
            options1.clientRoleType = AgoraClientRoleBroadcaster;
            options1.publishMediaPlayerAudioTrack = YES;
        //    options1.publishCustomAudioTrack = YES;
            [self.agoraKit updateChannelWithMediaOptions:options1];
        [sender setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }
  
}

- (IBAction)muteRecordingSignal:(UIButton *)sender {
    self.isMuteRecordingSignal = !self.isMuteRecordingSignal;
    if(self.isMuteRecordingSignal) {
        [self.agoraKit muteRecordingSignal:YES];
        [sender setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    } else {
        [self.agoraKit muteRecordingSignal:NO];
        [sender setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }
    
}

#pragma mark- <AgoraRtcEngineDelegate>
- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinChannel:(NSString*)channel withUid:(NSUInteger)uid elapsed:(NSInteger) elapsed {
    [self appendInfoToTableViewWithInfo:[NSString stringWithFormat:@"Self join channel with uid:%zd", uid]];
//    [self.agoraKit setDefaultAudioRouteToSpeakerphone:YES];
    [self startRecordPCM:AgoraSDKRawDataType_OnRecord];
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didJoinedOfUid:(NSUInteger)uid elapsed:(NSInteger)elapsed {
    [self appendInfoToTableViewWithInfo:[NSString stringWithFormat:@"Uid:%zd joined channel with elapsed:%zd", uid, elapsed]];
}

- (void)rtcEngineConnectionDidInterrupted:(AgoraRtcEngineKit *)engine {
    [self appendInfoToTableViewWithInfo:@"ConnectionDidInterrupted"];
}

- (void)rtcEngineConnectionDidLost:(AgoraRtcEngineKit *)engine {
    [self appendInfoToTableViewWithInfo:@"ConnectionDidLost"];
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOccurError:(AgoraErrorCode)errorCode {
    [self appendInfoToTableViewWithInfo:[NSString stringWithFormat:@"Error Code:%zd", errorCode]];
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didOfflineOfUid:(NSUInteger)uid reason:(AgoraUserOfflineReason)reason {
    [self appendInfoToTableViewWithInfo:[NSString stringWithFormat:@"Uid:%zd didOffline reason:%zd", uid, reason]];
}

- (void)rtcEngine:(AgoraRtcEngineKit *)engine didAudioRouteChanged:(AgoraAudioOutputRouting)routing {
    switch (routing) {
        case AgoraAudioOutputRoutingDefault:
            NSLog(@"AgoraRtc_AudioOutputRouting_Default");
            break;
        case AgoraAudioOutputRoutingHeadset:
            NSLog(@"AgoraRtc_AudioOutputRouting_Headset");
            break;
        case AgoraAudioOutputRoutingEarpiece:
            NSLog(@"AgoraRtc_AudioOutputRouting_Earpiece");
            break;
        case AgoraAudioOutputRoutingHeadsetNoMic:
            NSLog(@"AgoraRtc_AudioOutputRouting_HeadsetNoMic");
            break;
        case AgoraAudioOutputRoutingSpeakerphone:
            NSLog(@"AgoraRtc_AudioOutputRouting_Speakerphone");
            break;
        case AgoraAudioOutputRoutingLoudspeaker:
            NSLog(@"AgoraRtc_AudioOutputRouting_Loudspeaker");
            break;
        case AgoraAudioOutputRoutingHeadsetBluetooth:
            NSLog(@"AgoraRtc_AudioOutputRouting_HeadsetBluetooth");
            break;
        default:
            break;
    }
}

- (void)rtcEngineLocalAudioMixingDidFinish:(AgoraRtcEngineKit *)engine{
    
}



- (void)rtcEngine:(AgoraRtcEngineKit *)engine didClientRoleChanged:(AgoraClientRole)oldRole newRole:(AgoraClientRole)newRole {
    if (newRole == AgoraClientRoleBroadcaster) {
        [self appendInfoToTableViewWithInfo:@"Self changed to Broadcaster"];
    }
    else {
        [self appendInfoToTableViewWithInfo:@"Self changed to Audience"];
    }
}

#pragma mark- <UITableViewDataSource>
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.infoArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    InfoCell *cell =  [tableView dequeueReusableCellWithIdentifier:cellID];
    InfoModel *model = self.infoArray[indexPath.row];
    cell.model = model;
    return cell;
}

#pragma mark- <UITableViewDelegate>
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    InfoModel *model = self.infoArray[indexPath.row];
    return model.height;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 20;
}

#pragma mark- others
- (NSMutableArray *)infoArray {
    if (!_infoArray) {
        _infoArray = [NSMutableArray array];
    }
    return _infoArray;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark-
- (void )rtcEngine:(AgoraRtcEngineKit *)engine reportAudioVolumeIndicationOfSpeakers:(NSArray<AgoraRtcAudioVolumeInfo *> *)speakers totalVolume:(NSInteger)totalVolume {
    for(AgoraRtcAudioVolumeInfo *speaker in speakers) {
        NSLog(@"speakers : uid %ld , volume , %ld ",speaker.uid, speaker.volume);
    }
}

#pragma mark - rawdata
- (void )mediaDataPlugin:(AgoraMediaDataPlugin *)mediaDataPlugin didMixedAudioRawData:(AgoraAudioRawData *)audioRawData
{
    
    long success = 0;
       if (self.needWritePCM) {
           size_t writeBytes = audioRawData.samplesPerChannel * audioRawData.channels * sizeof(int16_t);
           success = fwrite(audioRawData.buffer, 1, writeBytes, fp_OnMixed_pcm);
       }
       NSLog(@"success %ld",success);
}

- (void) mediaDataPlugin:(AgoraMediaDataPlugin *)mediaDataPlugin didRecordAudioRawData:(AgoraAudioRawData *)audioRawData
{
    long success = 0;
    if (self.needWritePCM) {
        size_t writeBytes = audioRawData.samplesPerChannel * audioRawData.channels * sizeof(int16_t);
        success = fwrite(audioRawData.buffer, 1, writeBytes, fp_OnRecord_pcm);
    }
    NSLog(@"success %ld",success);
}

- (void)mediaDataPlugin:(AgoraMediaDataPlugin *)mediaDataPlugin willPlaybackBeforeMixingAudioRawData:(AgoraAudioRawData *)audioRawData
{
        long success = 0;
       if (self.needWritePCM) {
           size_t writeBytes = audioRawData.samplesPerChannel * audioRawData.channels * sizeof(int16_t);
           success = fwrite(audioRawData.buffer, 1, writeBytes, fp_PlayBackBeforeMixing_pcm);
       }
       NSLog(@"success %ld",success);
}

- (void)mediaDataPlugin:(AgoraMediaDataPlugin *)mediaDataPlugin willPlaybackAudioRawData:(AgoraAudioRawData *)audioRawData
{
        long success = 0;
       if (self.needWritePCM) {
           size_t writeBytes = audioRawData.samplesPerChannel * audioRawData.channels * sizeof(int16_t);
           success = fwrite(audioRawData.buffer, 1, writeBytes, fp_PlayBack_pcm);
       }
       NSLog(@"success %ld",success);
}

-(void)startRecordPCM:(AgoraSDKRawDataType)agoraSDKRawDataType
{
    
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *docuPath = [[documentPaths firstObject] stringByAppendingPathComponent:audioRawDataDir];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *audioFile = nil;
    switch (agoraSDKRawDataType) {
        case AgoraSDKRawDataType_OnRecord :
            if (fp_OnRecord_pcm == nil) {
                    if (![fileManager fileExistsAtPath:docuPath]) {
                        [fileManager createDirectoryAtPath:docuPath withIntermediateDirectories:YES attributes:nil error:nil];
                    }
                }
                audioFile = [docuPath stringByAppendingPathComponent:@"onRecord.pcm"];
                if ([fileManager fileExistsAtPath:audioFile]) {
                    [fileManager removeItemAtPath:audioFile error:nil];
                }
                fp_OnRecord_pcm = fopen([audioFile UTF8String], "wb++");
            break;
        case AgoraSDKRawDataType_OnMixed:
            if (fp_OnMixed_pcm == nil) {
                if (![fileManager fileExistsAtPath:docuPath]) {
                    [fileManager createDirectoryAtPath:docuPath withIntermediateDirectories:YES attributes:nil error:nil];
                }
            }
           audioFile = [docuPath stringByAppendingPathComponent:@"onMixed.pcm"];
            if ([fileManager fileExistsAtPath:audioFile]) {
                [fileManager removeItemAtPath:audioFile error:nil];
            }
            
            fp_OnMixed_pcm = fopen([audioFile UTF8String], "wb++");
            break;
        case AgoraSDKRawDataType_PlayBack:
            if (fp_PlayBack_pcm == nil) {
                if (![fileManager fileExistsAtPath:docuPath]) {
                    [fileManager createDirectoryAtPath:docuPath withIntermediateDirectories:YES attributes:nil error:nil];
                }
            }
            audioFile = [docuPath stringByAppendingPathComponent:@"onPlayBack.pcm"];
            if ([fileManager fileExistsAtPath:audioFile]) {
                [fileManager removeItemAtPath:audioFile error:nil];
            }
            
            fp_PlayBack_pcm = fopen([audioFile UTF8String], "wb++");
            break;
        case AgoraSDKRawDataType_PlayBackBeforeMixing:
            if (fp_PlayBackBeforeMixing_pcm == nil) {
                if (![fileManager fileExistsAtPath:docuPath]) {
                    [fileManager createDirectoryAtPath:docuPath withIntermediateDirectories:YES attributes:nil error:nil];
                }
            }
            audioFile = [docuPath stringByAppendingPathComponent:@"onPlayBackBeforeMixing.pcm"];
            if ([fileManager fileExistsAtPath:audioFile]) {
                [fileManager removeItemAtPath:audioFile error:nil];
            }
            
            fp_PlayBackBeforeMixing_pcm = fopen([audioFile UTF8String], "wb++");
            break;
            
        default:
            break;
    }
    
 
    NSLog(@"-----------------register---------------------");
    [self.agoraMediaDataPlugin setAudioDelegate:self];
}

-(void)stopRecordPCM:(AgoraSDKRawDataType)agoraSDKRawDataType
{
    NSLog(@"-----------------deregister---------------------");
    [self.agoraMediaDataPlugin setAudioDelegate:nil];
    
    switch (agoraSDKRawDataType) {
           case AgoraSDKRawDataType_OnRecord :
               fclose(fp_OnRecord_pcm);
//            [self convertPcmToWav:@"/onRecord.pcm"];
               break;
           case AgoraSDKRawDataType_OnMixed:
               fclose(fp_OnMixed_pcm);
               break;
           case AgoraSDKRawDataType_PlayBack:
              fclose(fp_PlayBack_pcm);
               break;
           case AgoraSDKRawDataType_PlayBackBeforeMixing:
              fclose(fp_PlayBackBeforeMixing_pcm);
               break;
           default:
               break;
       }
}

- (void) convertPcmToWav:(NSString *) pcmPath {
    NSArray *documentPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *docuPath = [[[documentPaths firstObject] stringByAppendingPathComponent:audioRawDataDir] stringByAppendingString:pcmPath];
    
    NSLog(@"docuPath is %@" , docuPath);
    
    BOOL isSuccess = [[PFAudio shareInstance] pcm2Wav:docuPath isDeleteSourchFile:NO];
    if(isSuccess) {
        NSLog(@"pcm convert to wav success");
    } else {
        NSLog(@"pcm convert to wav failed");
    }
}

@end
