// SPDX-License-Identifier: GPL-3.0-or-later
#import <AudioToolbox/AudioToolbox.h>
#include "mixer.hpp"
#include <atomic>
#include <map>
#include <mutex>
#include <cstdio>
extern "C" {
#include "i_sound.h"
#include "m_config.h"
#include "w_wad.h"
#include "z_zone.h"
int use_libsamplerate=0;
float libsamplerate_scale=1;
}
namespace {
DoomAudio::Mixer mixer;
std::mutex audioMutex;
std::map<int,DoomAudio::Sample> samples;
AudioQueueRef queue=nullptr;
std::atomic<bool> active{false};
bool prefix=true;
void fill(void*,AudioQueueRef aq,AudioQueueBufferRef buffer) {
    if (!active.load()) return;
    {
        std::lock_guard<std::mutex> lock(audioMutex);
        mixer.render(static_cast<int16_t*>(buffer->mAudioData),buffer->mAudioDataBytesCapacity/4);
    }
    buffer->mAudioDataByteSize=buffer->mAudioDataBytesCapacity;
    OSStatus status=AudioQueueEnqueueBuffer(aq,buffer,0,nullptr);
    if (status) active=false;
}
void stop() {
    active=false;
    if (queue) {AudioQueueStop(queue,true);AudioQueueDispose(queue,true);queue=nullptr;}
    std::lock_guard<std::mutex> lock(audioMutex);
    mixer={};samples.clear();
}
boolean init(boolean usePrefix) {
    prefix=usePrefix;
    AudioStreamBasicDescription format{};
    format.mSampleRate=DoomAudio::rate;format.mFormatID=kAudioFormatLinearPCM;
    format.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
    format.mBytesPerPacket=4;format.mFramesPerPacket=1;format.mBytesPerFrame=4;
    format.mChannelsPerFrame=2;format.mBitsPerChannel=16;
    OSStatus status=AudioQueueNewOutput(&format,fill,nullptr,nullptr,nullptr,0,&queue);
    if (!status) {
        active=true;
        for (unsigned i=0;i<3 && !status;++i) {
            AudioQueueBufferRef buffer=nullptr;status=AudioQueueAllocateBuffer(queue,2048*4,&buffer);
            if (!status) fill(nullptr,queue,buffer);
        }
        if (!status && active) status=AudioQueueStart(queue,nullptr);
    }
    if (status || !active) {
        std::fprintf(stderr,"DOOM: AudioQueue output failed (%d)\n",int(status));stop();return false;
    }
    std::puts("DOOM: AudioQueue started, 44100 Hz stereo PCM");return true;
}
int lump(sfxinfo_t* effect) {
    char name[12];std::snprintf(name,sizeof(name),"%s%.8s",prefix?"ds":"",effect->name);
    return W_CheckNumForName(name);
}
void params(int channel,int volume,int separation) {
    if (channel<0 || channel>=int(mixer.channels.size())) return;
    std::lock_guard<std::mutex> lock(audioMutex);
    mixer.channels[channel].volume=std::clamp(volume,0,127);
    mixer.channels[channel].separation=std::clamp(separation,0,254);
}
int play(sfxinfo_t* effect,int channel,int volume,int separation) {
    if (!active || channel<0 || channel>=int(mixer.channels.size())) return -1;
    int index=effect->lumpnum;if (index<0) index=lump(effect);
    if (index<0) return -1;
    if (!samples.count(index)) {
        int length=W_LumpLength(index);if (length<8) return -1;
        auto data=static_cast<const uint8_t*>(W_CacheLumpNum(index,PU_STATIC));
        auto decoded=DoomAudio::decode(data,length);W_ReleaseLumpNum(index);
        std::lock_guard<std::mutex> lock(audioMutex);
        samples.emplace(index,std::move(decoded));
    }
    std::lock_guard<std::mutex> lock(audioMutex);
    const auto& sample=samples.at(index);if (sample.pcm.empty()) return -1;
    mixer.channels[channel]={&sample,0,unsigned(std::clamp(volume,0,127)),unsigned(std::clamp(separation,0,254))};
    return channel;
}
void stopChannel(int channel) {
    if (channel<0 || channel>=int(mixer.channels.size())) return;
    std::lock_guard<std::mutex> lock(audioMutex);mixer.channels[channel].sample=nullptr;
}
boolean playing(int channel) {
    if (channel<0 || channel>=int(mixer.channels.size())) return false;
    std::lock_guard<std::mutex> lock(audioMutex);return mixer.channels[channel].sample!=nullptr;
}
void update() {}
void cache(sfxinfo_t*,int) {}
// Music is an independent backend; sound effects do not depend on MIDI/OPL.
boolean noMusic() { return false; }
void musicVolume(int) {}
void* song(void*,int) { return nullptr; }
void unSong(void*) {}
void playSong(void*,boolean) {}
snddevice_t devices[]={SNDDEVICE_SB};
}
extern "C" {
sound_module_t DG_sound_module={devices,1,init,stop,lump,update,params,play,stopChannel,playing,cache};
music_module_t DG_music_module={devices,1,noMusic,update,musicVolume,update,update,song,unSong,playSong,update,noMusic,update};
}
void doomAudioStop() {stop();}
