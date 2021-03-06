/*
Copyright © 2010-2012 Brian S. Hall

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2 or later as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
*/
#import "MorseRenderer.h"
#import "LED.h"

#define __MORSE_RENDERER_DEBUG__ 0

NSString* MorseRendererFinishedNotification = @"MorseRendererFinishedNotification";
NSString* MorseRendererStartedWordNotification = @"MorseRendererStartedWordNotification";
static const float gSampleRate = 44100.0f;

@interface MorseRenderer (Private)
-(OSStatus)_initAUGraph;
-(void)_updatePadding;
-(void)setAgenda:(NSString*)string withDelay:(BOOL)del;
@end



static OSStatus RendererCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                           const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                           UInt32 inNumberFrames, AudioBufferList* ioData);
static OSStatus NoiseCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                        const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                        UInt32 inNumberFrames, AudioBufferList* ioData);

static void init_3band_state(EQSTATE* es, int lowfreq, int highfreq, int mixfreq);
static double do_3band(EQSTATE* es, double sample);

static unsigned Renderer(MorseRenderState* inState, UInt32 inNumberFrames,
                         AudioBufferList* ioData);
static void local_SendNote(MorseRenderState* state);
static void local_SendRange(MorseRenderState* state);

#if __MORSE_RENDERER_DEBUG__
static void hexdump(void *data, int size);
#endif

// Audio processing callback
static OSStatus  RendererCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                           const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                           UInt32 inNumberFrames, AudioBufferList* ioData)
{
  MorseRenderState* state = (MorseRenderState*)inRefCon;
  unsigned s = Renderer(state, inNumberFrames, ioData);
  if (!s) *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
  return noErr;
}

static OSStatus  NoiseCB(void* inRefCon, AudioUnitRenderActionFlags* ioActionFlags,
                           const AudioTimeStamp* inTimeStamp, UInt32 inBusNumber,
                           UInt32 inNumberFrames, AudioBufferList* ioData)
{
  MorseRenderState* state = (MorseRenderState*)inRefCon;
  //printf("qrn %f\n", state->qrn);
  float* lBuffer = ioData->mBuffers[0].mData;
  float* rBuffer = ioData->mBuffers[1].mData;
  UInt32 i;
  float inv = (float)(1.0f / INT32_MAX);
  for (i = 0; i < inNumberFrames; i++)
  {
    float lsample = 0.0f;
    float rsample = 0.0f;
    int32_t rnd = arc4random();
    // White Noise
    if (state->qrn > 0.0)
    {
      lsample = rnd * inv;
      lsample = do_3band(&state->eq, lsample);
    }
    float m = state->qrn * state->amp;
    lsample *= m;
    if (lsample > 1.0) lsample = 1.0;
    if (lsample < -1.0) lsample = -1.0;
    rsample = lsample;
    if (lsample != 0.0f && state->pan != 0.5f)
    {
      lsample *= ((-2.0f * state->pan) + 2.0f);
      rsample *= (2.0f * state->pan);
    }
    *lBuffer++ = lsample;
    *rBuffer++ = rsample;
  }
  return noErr;
}

//----------------------------------------------------------------------------
//
//                                3 Band EQ :)
//
// EQ.C - Main Source file for 3 band EQ
//
// (c) Neil C / Etanza Systems / 2K6
//
// Shouts / Loves / Moans = etanza at lycos dot co dot uk 
//
// This work is hereby placed in the public domain for all purposes, including
// use in commercial applications.
//
// The author assumes NO RESPONSIBILITY for any problems caused by the use of
// this software.
//
//----------------------------------------------------------------------------

// NOTES :
//
// - Original filter code by Paul Kellet (musicdsp.pdf)
//
// - Uses 4 first order filters in series, should give 24dB per octave
//
// - Now with P4 Denormal fix :)



// -----------
//| Constants |
// -----------

static double vsa = (1.0 / 4294967295.0);   // Very small amount (Denormal Fix)


// ---------------
//| Initialise EQ |
// ---------------

// Recommended frequencies are ...
//
//  lowfreq  = 880  Hz
//  highfreq = 5000 Hz
//
// Set mixfreq to whatever rate your system is using (eg 48Khz)

static void init_3band_state(EQSTATE* es, int lowfreq, int highfreq, int mixfreq)
{
  // Clear state 

  memset(es,0,sizeof(EQSTATE));

  // Set Low/Mid/High gains to unity

  es->lg = 0.8;
  es->mg = 1.0;
  es->hg = 0.1;

  // Calculate filter cutoff frequencies

  es->lf = 2 * sin(M_PI * ((double)lowfreq / (double)mixfreq)); 
  es->hf = 2 * sin(M_PI * ((double)highfreq / (double)mixfreq));
}


// ---------------
//| EQ one sample |
// ---------------

// - sample can be any range you like :)
//
// Note that the output will depend on the gain settings for each band 
// (especially the bass) so may require clipping before output, but you 
// knew that anyway :)

static double do_3band(EQSTATE* es, double sample)
{
  // Locals

  double  l,m,h;      // Low / Mid / High - Sample Values

  // Filter #1 (lowpass)

  es->f1p0  += (es->lf * (sample   - es->f1p0)) + vsa;
  es->f1p1  += (es->lf * (es->f1p0 - es->f1p1));
  es->f1p2  += (es->lf * (es->f1p1 - es->f1p2));
  es->f1p3  += (es->lf * (es->f1p2 - es->f1p3));

  l          = es->f1p3;

  // Filter #2 (highpass)
  
  es->f2p0  += (es->hf * (sample   - es->f2p0)) + vsa;
  es->f2p1  += (es->hf * (es->f2p0 - es->f2p1));
  es->f2p2  += (es->hf * (es->f2p1 - es->f2p2));
  es->f2p3  += (es->hf * (es->f2p2 - es->f2p3));

  h          = es->sdm3 - es->f2p3;

  // Calculate midrange (signal - (low + high))

  m          = es->sdm3 - (h + l);

  // Scale, Combine and store

  l         *= es->lg;
  m         *= es->mg;
  h         *= es->hg;

  // Shuffle history buffer 

  es->sdm3   = es->sdm2;
  es->sdm2   = es->sdm1;
  es->sdm1   = sample;                

  // Return result

  return(l + m + h);
}

static unsigned Renderer(MorseRenderState* state, UInt32 inNumberFrames,
                         AudioBufferList* ioData)
{
  unsigned samples = 0;
  float fadeSamples = gSampleRate * 0.004f;
  float phase = state->phase;
  float amp = state->amp;
  float freq = state->freq;
  float ampz = state->ampz;
  float freqz = state->freqz;
  float decay = 1.0f;
  float* lBuffer = ioData->mBuffers[0].mData;
  float* rBuffer = ioData->mBuffers[1].mData;
  uint16_t* item = NULL;
  uint16_t code = 0;
  int waveType = state->waveType;
  BOOL atEnd = (state->agendaCount < 1 || state->agendaCount <= state->agendaDone);
  //NSLog(@"atEnd (%d > %d) = %s phase %f mode %d",
  //      state->agendaCount, state->agendaDone, (atEnd)? "yes":"no", phase, state->mode);
  if (state->agenda && state->play)
  {
    item = &(state->agenda)[state->agendaDone];
    //local_SendRange(state);
    //NSLog(@"range");
    code = *item;
  }
  uint16_t lengthBits = code & 0x0007;
  uint16_t elements = lengthBits? lengthBits:1;
  BOOL on = NO;
  float dits = 1.0f;
  unsigned i;
  for (i = 0; i < inNumberFrames; i++)
  {
    float lsample = 0.0f;
    float rsample = 0.0f;
    if ((item && state->agendaDone < state->agendaCount) ||
         state->mode == MorseRendererOnMode ||
         state->mode == MorseRendererDecayMode)
    {
      if (state->mode == MorseRendererDecayMode && state->lastMode != MorseRendererDecayMode)
      {
        state->agendaItemElementSamplesDone = 0;
        state->lastMode = MorseRendererDecayMode;
      }
      if (state->mode == MorseRendererOnMode && state->lastMode != MorseRendererOnMode)
      {
        state->agendaItemElementSamplesDone = 0;
        state->lastMode = MorseRendererOnMode;
      }
      if (code == MorseInterelementSpace || state->doingInterelementSpace) dits = MorseDitUnits;
      else if (code == MorseIntercharacterSpace) dits = MorseDahUnits;
      else if (code == MorseInterwordSpace || state->doingLoopSpace) dits = MorseInterwordUnits;
      else
      {
        BOOL bit = (code >> (3 + state->agendaItemElementsDone)) & 0x0001;
        dits = (bit)? MorseDahUnits:MorseDitUnits;
        if (dits == MorseDahUnits && state->weight != 3.0) dits = state->weight;
        on = YES;
        if (state->mode == MorseRendererDecayMode)
        {
          decay = (fadeSamples - state->agendaItemElementSamplesDone) * (1.0/fadeSamples);
          decay = sin(M_PI_2 * decay);
          if (state->agendaItemElementSamplesDone >= fadeSamples)
          {
            state->mode = MorseRendererOffMode;
          }
          if (decay < 0.0f) decay = 0.0f;
          //if (decay != 1.0f) NSLog(@"decay %f from samples %d, %f mode %d (%f)",
          //                        decay, state->agendaItemElementsDone, (1.0/fadeSamples), state->mode, fadeSamples);
        }
        else if (state->agendaItemElementSamplesDone < fadeSamples)
        {
          decay = state->agendaItemElementSamplesDone * (1.0/fadeSamples);
          decay = sin(M_PI_2 * decay);
          //if (decay != 1.0f) NSLog(@"decay %f from state->agendaItemElementSamplesDone (%d) * (1.0/%d)", decay, state->agendaItemElementSamplesDone, fadeSamples);
        }
        else if (state->mode != MorseRendererOnMode)
        {
          unsigned remaining = (dits * state->samplesPerDit) - state->agendaItemElementSamplesDone;
          if (remaining < fadeSamples)
          {
            decay = remaining * (1.0/fadeSamples);
            decay = sin(M_PI_2 * decay);
          }
          else decay = 1.0f;
          //if (decay != 1.0f) NSLog(@"decay %f from remaining (%d) * %f", decay, remaining, (1.0/fadeSamples));
        }
      }
      if (!state->doingLoopSpace &&
          (state->agendaItemElementsDone < elements ||
           state->mode == MorseRendererOnMode ||
           state->mode == MorseRendererDecayMode))
      {
        // This sample is on if not doing interelement and this is not a space character.
        if ((lengthBits > 0 && !state->doingInterelementSpace) ||
            state->mode == MorseRendererOnMode ||
            state->mode == MorseRendererDecayMode)
        {
          if (waveType == MorseRendererWaveSine)
          {
            lsample = ampz * sinf(phase);
          }
          else if (waveType == MorseRendererWaveSaw)
          {
            lsample = ampz - (ampz/M_PI*phase);
          }
          else if (waveType == MorseRendererWaveSquare)
          {
            lsample = (phase < M_PI)? ampz:-ampz;
          }
          else /*if (waveType == MorseRendererWaveTriangle)*/
          {
            if (phase < M_PI) lsample = -ampz + (2.0f*ampz/M_PI*phase);
            else lsample = (3.0f*ampz) - (2.0f*ampz/M_PI*phase);
          }
          // Update phase and wrap around if necessary
          //phase += ((2.0f * M_PI * freq) / gSampleRate);
          phase += freq;
          if (phase > M_PI * 2.0f) phase -= M_PI * 2.0f;
          //printf("phase %f from %f\n", phase, freqz);
          if (decay != 1.0f)
          {
            lsample *= decay;
            //printf("applying decay: %f from %f * %f %f)\n", lsample * decay, decay, lsample, phase);
          }
          rsample = lsample;
          if (lsample != 0.0f)
          {
            lsample *= ((-2.0f * state->pan) + 2.0f);
            rsample *= (2.0f * state->pan);
          }
        }
      }
    }
    *lBuffer++ = lsample;
    *rBuffer++ = rsample;
    ampz  = 0.001f * amp  + 0.999f * ampz;
    freqz = 0.001f * freq + 0.999f * freqz;
    state->agendaItemElementSamplesDone++;
    if (state->wasOn != on)
    {
      state->wasOn = on;
      //if (state->flash) manipulate_led(on);
      if (state->flash) [state->led setValue:on];
    }
    if (item)
    {
      float needed = dits * state->samplesPerDit;
      if (!on)
      {
        if (dits == MorseDahUnits && state->intercharacter > 0.0L) needed = state->intercharacter;
        else if (dits == MorseInterwordUnits && state->interword > 0.0L) needed = state->interword;
      }
      if (state->agendaItemElementSamplesDone >= needed)
      {
        // If this is a nonfinal element, do interelement space. Otherwise move to next element.
        if (!state->doingInterelementSpace && on && state->agendaItemElementsDone < elements-1)
        {
          state->doingInterelementSpace = YES;
          on = NO;
        }
        else
        {
          if (state->doingLoopSpace)
          {
            local_SendRange(state);
          }
          else (state->agendaItemElementsDone)++;
          state->doingInterelementSpace = NO;
          state->doingLoopSpace = NO;
          decay = 0.0f;
        }
        state->agendaItemElementSamplesDone = 0;
        phase = 0.0f;
        freqz = freq;
        ampz = amp;
        if (state->agendaItemElementsDone >= elements)
        {
          state->agendaDone++;
          local_SendRange(state);
          state->agendaItemElementsDone = 0;
          if (state->mode != MorseRendererOnMode) item = &(state->agenda)[state->agendaDone];
        }
        //NSLog(@"%d/%d elements done", state->agendaItemElementsDone, elements);
        if (state->agendaDone >= state->agendaCount)
        {
          if (state->loop && state->mode != MorseRendererOnMode)
          {
            state->doingLoopSpace = YES;
            state->agendaDone = 0;
            item = &(state->agenda)[0];
          }
          else
          {
            item = NULL;
            atEnd = YES;
          }
        }
        //NSLog(@"item 0x%X", item);
      }
    }
    if (item) code = *item;
    else code = 0;
    lengthBits = code & 0x0007;
    elements = lengthBits? lengthBits:1;
    if (atEnd) state->play = NO;
    else samples++;
  }
  //printf("Now setting phase to %f\n", phase);
  state->phase = phase;
  state->freqz = freqz;
  state->ampz = ampz;
  state->lastMode = state->mode;
  if (atEnd && !state->sentNote)
  {
    state->sentNote = YES;
    local_SendNote(state);
  }
  return samples;
}

static void local_SendNote(MorseRenderState* state)
{
  if (state->sendsNote)
  {
    NSAutoreleasePool* arp = [[NSAutoreleasePool alloc] init];
    NSNotification* note = [NSNotification notificationWithName:MorseRendererFinishedNotification object:nil];
    [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    [arp release];
  }
}

static void local_SendRange(MorseRenderState* state)
{
  if (state->sendsNote)
  {
    NSAutoreleasePool* arp = [[NSAutoreleasePool alloc] init];
    NSString* s = [state->offsets objectForKey:[NSNumber numberWithUnsignedShort:state->agendaDone]];
    //NSLog(@"%@ for %d", s, state->agendaDone);
    if (s)
    {
      NSNotification* note = [NSNotification notificationWithName:MorseRendererStartedWordNotification object:s];
      [[NSNotificationCenter defaultCenter] performSelectorOnMainThread:@selector(postNotification:) withObject:note waitUntilDone:NO];
    }
    [arp release];
  }
}

@implementation MorseRenderer
-(id)init
{
  self = [super init];
  _string = [[NSMutableString alloc] init];
  OSStatus err = noErr;
  _state.led = [[LED alloc] init];
  err = [self _initAUGraph];
  if (err)
  {
    [self dealloc];
    self = nil;
  }
  //CAShow(_ag);
  return self;
}

-(OSStatus)_initAUGraph
{
  OSStatus result = NewAUGraph(&_ag);
  if (result) return NO;
  // AUNodes represent AudioUnits on the AUGraph and provide an
  // easy means for connecting audioUnits together.
  AUNode outputNode;
  AUNode mixerNode;
  // Create AudioComponentDescriptions for the AUs we want in the graph
  // mixer component
  ComponentDescription mixer_desc;
  mixer_desc.componentType = kAudioUnitType_Mixer;
  mixer_desc.componentSubType = kAudioUnitSubType_StereoMixer;
  mixer_desc.componentFlags = 0;
  mixer_desc.componentFlagsMask = 0;
  mixer_desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  //  output component
  ComponentDescription output_desc;
  output_desc.componentType = kAudioUnitType_Output;
  output_desc.componentSubType = kAudioUnitSubType_DefaultOutput;
  output_desc.componentFlags = 0;
  output_desc.componentFlagsMask = 0;
  output_desc.componentManufacturer = kAudioUnitManufacturer_Apple;
  // Add nodes to the graph to hold our AudioUnits,
  // You pass in a reference to the  AudioComponentDescription
  // and get back an  AudioUnit
  result = AUGraphAddNode(_ag, &output_desc, &outputNode);
  if (result) return result;
  result = AUGraphAddNode(_ag, &mixer_desc, &mixerNode );
  if (result) return result;
  // Now we can manage connections using nodes in the graph.
  // Connect the mixer node's output to the output node's input
  result = AUGraphConnectNodeInput(_ag, mixerNode, 0, outputNode, 0);
  if (result) return result;
  // open the graph AudioUnits are open but not initialized (no resource allocation occurs here)
  result = AUGraphOpen(_ag);
  if (result) return result;
  // Get a link to the mixer AU so we can talk to it later
  result = AUGraphNodeInfo(_ag, mixerNode, NULL, &_mixer);
  if (result) return result;
  //************************************************************
  //*** Make connections to the mixer unit's inputs ***
  //************************************************************
  // Set the number of input busses on the Mixer Unit
  UInt32 numbuses = 2;
  UInt32 size = sizeof(numbuses);
  result = AudioUnitSetProperty(_mixer, kAudioUnitProperty_ElementCount,
                                kAudioUnitScope_Input, 0, &numbuses, size);
  if (result) return result;
  numbuses = 2; // Clang analyzer assumes the pass by ref may have changed it.
  AudioStreamBasicDescription desc;
  desc.mSampleRate = gSampleRate;
  desc.mFormatID = kAudioFormatLinearPCM;
#if TARGET_RT_BIG_ENDIAN
    desc.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
#else
    desc.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
#endif
  desc.mBytesPerPacket = 4;
  desc.mFramesPerPacket = 1;
  desc.mBytesPerFrame = 4;
  desc.mChannelsPerFrame = 2;
  desc.mBitsPerChannel = 32;
  AURenderCallback cbs[2] = {&RendererCB,&NoiseCB};
  void* rcs[2] = {&_state,&_state};
  // Loop through and setup a callback for each source you want to send to the mixer.
  // Right now we are only doing a single bus so we could do without the loop.
  int i;
  for (i = 0; i < numbuses; i++)
  {
    // Setup render callback struct
    // This struct describes the function that will be called
    // to provide a buffer of audio samples for the mixer unit.
    AURenderCallbackStruct rcbs;
    rcbs.inputProc = cbs[i];
    rcbs.inputProcRefCon = rcs[i];
    // Set a callback for the specified node's specified input
    result = AudioUnitSetProperty(_mixer, kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input, i, &rcbs,
                                  sizeof(AURenderCallbackStruct)); 
    //result = AUGraphSetNodeInputCallback(_ag, mixerNode, i, &rcbs);
    if (result) return result;
    // Apply the modified CAStreamBasicDescription to the mixer input bus
    result = AudioUnitSetProperty(_mixer, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, i,
                                  &desc, sizeof(desc));
    if (result) return result;
  }
  // Apply the Description to the mixer output bus
  result = AudioUnitSetProperty(_mixer, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Output, 0,
                                &desc, sizeof(desc));
  if (result) return result;
  //************************************************************
  //*** Setup the audio output stream ***
  //************************************************************
  // Apply the modified CAStreamBasicDescription to the output Audio Unit
  result = AudioUnitSetProperty(_mixer, kAudioUnitProperty_StreamFormat,
                                kAudioUnitScope_Output, 0,
                                &desc, sizeof(desc));
  if (result) return result;
  // Once everything is set up call initialize to validate connections
  return AUGraphInitialize(_ag);
}

-(id)copyWithZone:(NSZone*)z
{
  MorseRenderer* cpy = [[MorseRenderer alloc] init];
  [cpy setString:_string withDelay:NO];
  [cpy setState:&_state];
  return cpy;
}

-(void)dealloc
{
  [self stop];
  DisposeAUGraph(_ag);
  if (_state.agenda) free(_state.agenda);
  if (_state.offsets) [_state.offsets release];
  if (_string) [_string release];
  [super dealloc];
}

-(void)setAmp:(float)val
{
  _state.amp = val;
  _state.ampz = val;
}

-(void)setFreq:(float)val
{
  _state.freq = val * 2.0f * M_PI / gSampleRate;
  _state.freqz = _state.freq;
}

-(void)setWPM:(float)val
{
  _state.wpm = val;
  [self _updatePadding];
}

-(void)setCWPM:(float)val
{
  _state.cwpm = val;
  _state.samplesPerDit = 1.2f/val * gSampleRate;
  [self _updatePadding];
}

-(void)setPan:(float)val
{
  if (val < 0.0) val = 0.0f;
  if (val > 1.0) val = 1.0f;
  _state.pan = val;
}


-(void)setLoop:(BOOL)flag {_state.loop = flag;}
-(void)setQRN:(float)val { _state.qrn = val; }
-(void)setWeight:(float)val { _state.weight = val; }
-(void)setWaveType:(MorseRendererWaveType)type { _state.waveType = type; }
-(BOOL)flash { return _state.flash; }

-(void)setFlash:(BOOL)flag
{
  [_state.led setValue:0];
  _state.flash = flag;
}

-(void)_updatePadding
{
  MorseSpacing spacing = [Morse spacingForWPM:_state.wpm CWPM:_state.cwpm];
  _state.intercharacter = spacing.intercharacterMilliseconds / 1000.0L * gSampleRate;
  _state.interword = spacing.interwordMilliseconds / 1000.0L * gSampleRate;
  //NSLog(@"intercharacter %f sec, interword %f sec", tc, tw);
}

-(void)setAgenda:(NSString*)s withDelay:(BOOL)del
{
  if (_state.agenda) free(_state.agenda);
  _state.agenda = NULL;
  if (_state.offsets) [_state.offsets release];
  _state.offsets = nil;
  if (s)
  {
    _state.agenda = [Morse morseFromString:s withDelay:del
                           length:&_state.agendaCount
                           offsets:&(_state.offsets)];
    [_state.offsets retain];
  }
}

-(void)setMode:(MorseRendererMode)mode
{
  if (_state.mode != mode)
  {
    if (mode == MorseRendererOffMode) mode = MorseRendererDecayMode;
    _state.mode = mode;
    if (mode == MorseRendererAgendaMode) [self stop];
    else if (mode != MorseRendererDecayMode) [self start:nil withDelay:NO];
  }
}

-(void)setSendsNote:(BOOL)flag
{
  _state.sendsNote = flag;
}

-(void)start:(NSString*)s withDelay:(BOOL)del
{
  [self setString:(s)? s:@"" withDelay:del];
  if (!_state.play)
  {
    OSStatus err = AUGraphStart(_ag);
    //CAShow(_ag);
    local_SendRange(&_state);
    if (err) printf ("AUGraphStart=%ld\n", (long)err);
    else _state.play = YES;
  }
}

-(void)stop
{
  (void)AUGraphStop(_ag);
  if (_state.agenda) free(_state.agenda);
  _state.agenda = NULL;
  _state.agendaCount = 0;
  _state.agendaDone = 0;
  _state.agendaItemElementsDone = 0;
  _state.agendaItemElementSamplesDone = 0;
  _state.doingInterelementSpace = NO;
  _state.doingLoopSpace = NO;
  _state.play = NO;
  _state.wasOn = NO;
  _state.sentNote = NO;
  [_state.led setValue:0];
}

-(BOOL)isPlaying {return _state.play;}

-(NSString*)string { return _string; }

-(void)setString:(NSString*)s withDelay:(BOOL)del
{
  [_string setString:s];
  if (s) [self setAgenda:s withDelay:del];
  // initialize phase and de-zipper filters.
  _state.phase = 0.0f;
  _state.freqz = _state.freq;
  _state.ampz = _state.amp;
  _state.agendaDone = 0;
  _state.agendaItemElementsDone = 0;
  _state.agendaItemElementSamplesDone = 0;
  init_3band_state(&_state.eq, 200, 2000, gSampleRate);
}

-(void)setState:(MorseRenderState*)s
{
  NSDictionary* oldOffsets = _state.offsets;
  if (oldOffsets) [oldOffsets release];
  memcpy(&_state, s, sizeof(_state));
  _state.offsets = [_state.offsets copy];
}

#define BUFF_SIZE 0x20000L
-(void)exportAIFF:(NSURL*)url
{
  //AudioStreamBasicDescription destFormat;
  _state.sendsNote = NO;
  float* buff1 = NULL;
  float* buff2 = NULL;
  buff1 = malloc(BUFF_SIZE);
  buff2 = malloc(BUFF_SIZE);
  AudioBufferList* abl = malloc(sizeof(*abl) + sizeof(abl->mBuffers[0]));
  abl->mNumberBuffers = 2;
  abl->mBuffers[0].mData = buff1;
  abl->mBuffers[0].mDataByteSize = BUFF_SIZE;
  abl->mBuffers[0].mNumberChannels = 1;
  abl->mBuffers[1].mData = buff2;
  abl->mBuffers[1].mDataByteSize = BUFF_SIZE;
  abl->mBuffers[1].mNumberChannels = 1;
  if (_state.amp == 0.0) [self setAmp:0.5];
  [self setLoop:NO];
  [self setFlash:NO];
  if (buff1 && buff2)
  {
    AudioStreamBasicDescription streamFormat;
    streamFormat.mSampleRate = gSampleRate;
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsPacked;
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBitsPerChannel = 16;
    streamFormat.mBytesPerFrame = 4;
    streamFormat.mBytesPerPacket = 4;
    SInt64 packetidx = 0;
    AudioFileID fileID;
    OSStatus err = AudioFileCreateWithURL((CFURLRef)url, kAudioFileAIFFType, &streamFormat, kAudioFileFlags_EraseFile, &fileID);
    if (err)
    {
      NSLog(@"AudioFileCreateWithURL: err %d %.4s", err, &err);
      return;
    }
    else
    {
      _state.play = YES;
      //NSLog(@"AudioFileCreateWithURL %.4s rate %f file %d", &err, streamFormat.mSampleRate, fileID);
      while (_state.play)
      {
        unsigned samples = Renderer(&_state, BUFF_SIZE/sizeof(float), abl);
        if (!samples) break;
        unsigned i;
        int16_t* buff3 = malloc(samples * 2 * sizeof(int16_t));
        unsigned i3 = 0;
        UInt32 ioNumPackets = samples;
        for (i = 0; i < samples; i++)
        {
          int16_t samp = 32767.0 * buff1[i];
          buff3[i3++] = CFSwapInt16HostToBig(samp);
          samp = 32767.0 * buff2[i];
          buff3[i3++] = CFSwapInt16HostToBig(samp);
        }
        //hexdump(buff3, 1000);
        err = AudioFileWritePackets(fileID, false, samples, NULL, packetidx, &ioNumPackets, buff3);
        if (err) NSLog(@"AudioFileWritePackets: err %d", err);
        packetidx += ioNumPackets;
        free(buff3);
      }
      AudioFileClose(fileID);
    }
    if (buff1) free(buff1);
    if (buff2) free(buff2);
    if (abl) free(abl);
  }
}
@end

#if __MORSE_RENDERER_DEBUG__
static void hexdump(void *data, int size)
{
  /* dumps size bytes of *data to stdout. Looks like:
   * [0000] 75 6E 6B 6E 6F 77 6E 20
   *                  30 FF 00 00 00 00 39 00 unknown 0.....9.
   * (in a single line of course)
   */
  unsigned char *p = data;
  unsigned char c;
  int n;
  char bytestr[4] = {0};
  char addrstr[10] = {0};
  char hexstr[ 16*3 + 5] = {0};
  char charstr[16*1 + 5] = {0};
  for (n=1;n<=size;n++)
  {
    if (n%16 == 1)
    {
      /* store address for this line */
      snprintf(addrstr, sizeof(addrstr), "%.4x", ((unsigned int)p-(unsigned int)data));
    }
    c = *p;
    if (isalnum(c) == 0)
    {
      c = '.';
    }
    /* store hex str (for left side) */
    snprintf(bytestr, sizeof(bytestr), "%02X ", *p);
    strncat(hexstr, bytestr, sizeof(hexstr)-strlen(hexstr)-1);
    /* store char str (for right side) */
    snprintf(bytestr, sizeof(bytestr), "%c", c);
    strncat(charstr, bytestr, sizeof(charstr)-strlen(charstr)-1);
    if (n%16 == 0)
    { 
      /* line completed */
      printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
      hexstr[0] = 0;
      charstr[0] = 0;
    }
    else if (n%8 == 0)
    {
      /* half line: add whitespaces */
      strncat(hexstr, "  ", sizeof(hexstr)-strlen(hexstr)-1);
      strncat(charstr, " ", sizeof(charstr)-strlen(charstr)-1);
    }
    p++; /* next byte */
  }
  if (strlen(hexstr) > 0)
  {
    /* print rest of buffer if not empty */
    printf("[%4.4s]   %-50.50s  %s\n", addrstr, hexstr, charstr);
  }
}
#endif


