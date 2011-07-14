/*
 * Copyright (c) 1991 Paul J. Drongowski.
 * Copyright (c) 1992 Joe Dellinger.
 * Copyright (c) 2005 Eric S. Raymond.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
/*
 * Return-Path: <pjd@cadillac.siemens.com>
 * Received: from cadillac.siemens.com by montebello.soest.hawaii.edu (4.1/montebello-MX-1.9)
 *      id AA01487; Mon, 10 Aug 92 03:21:41 HST
 * Received: from kevin.siemens.com by cadillac.siemens.com (4.1/SMI-4.0)
 *      id AA25847; Mon, 10 Aug 92 09:21:37 EDT
 * Date: Mon, 10 Aug 92 09:21:37 EDT
 * From: pjd@cadillac.siemens.com (paul j. drongowski)
 * Message-Id: <9208101321.AA25847@cadillac.siemens.com>
 * To: joe@montebello.soest.hawaii.edu
 * Status: RO
 */

/*
 * This copy is slightly hacked by Joe Dellinger, August 1992
 * And some more... November 1992
 *
 * Partially re-written by "murray@vs6.scri.fsu.edu"
 * to use better grammar and to avoid some nonsensical
 * responses (like claiming to be a person who's been licensed
 * longer than they've been alive!), Jan 1994
 *
 * Those improvements merged with others by Joe Dellinger, Oct 1994
 */

/*
 * Generate QSO
 */

/*
 * When run, this program generates a single QSO. The form of the
 * QSO is similar to QSO's one would expect to hear at a code test.
 * It begins with a series of V's (commented out in this version),
 * callsigns of the receiver and
 * sender, followed by a few sentences about weather, name,
 * occupation, etc. The QSO ends with the callsigns of the receiver
 * and sender.
 *
 * All output is produced using "printf." This should make the
 * program easy to port. Output can be piped into another program
 * such as sparc-morse on the Sun or it can be redirected into
 * a file (without viewing the contents of course!)
 *
 * The program design is similar to a "random poetry generator"
 * or "mad-libs." Each QSO form is generated by its own C function,
 * such as "PutForm1." Each function calls other C functions to
 * produce the sentences in the QSO. The sentence forms are
 * selected somewhat randomly as well as any blanks to be filled.
 * Words and phrases are selected from several lists such as
 * "Transceiver," "Antenna," "Job," etc. Sometimes this scheme is
 * clever as in the formation of city names. Sometimes it is
 * stupidly simple-minded and grammatical agreement is lost.
 * By the way, the callsigns are real and were picked from
 * rec.radio.amateur.misc on USENET.
 *
 * The program was constructed in C for Sun workstations. It uses
 * the library function "drand48" in function "Roll" to produce
 * pseudo-random numbers. The library function "srand48" and "time"
 * in "main" are used to set the pseudo-random number seed.
 *
 * Known problems and caveats? Hey, it`s software! All Morse
 * training programs handle the procedural signs (e.g., AR, SK)
 * differently. The function "PutQSO" currently prints "+ %"
 * for the AR and SK at the end of the QSO. These may be ignored,
 * mapped into something else, or just plain cause your training
 * program to roll over and play dead. I don`t know. This is a
 * cheap hack.
 *
 * And speaking of cheap... The program will not generate all
 * characters and pro-signs that are found on an "official" code
 * test. This program is for practice only and should be supplemented
 * with lots of random code.
 *
 * Always have fun!
 */
/* Translated into Objective C and semi-librarified (or de-printf-ified)
   by Brian "Moses" Hall K8TIY in 2011.
*/

#include <sys/types.h>
#include <stdio.h>
#include <time.h>
#include "QSO.h"

static NSString* A_Or_An(NSString* string);
static BOOL is_vowel(unichar first);

NSDictionary* gDict = nil;

@implementation QSO
-(id)init
{
  self = [super init];
  _qso = [[NSMutableString alloc] init];
  _age = Roll(70) + 16;
   unichar ol = 0x0305;
  _bt = [[NSString alloc] initWithFormat:(Roll(2))? @" B%CT%C":@".", ol, ol];
  [self PutQSO];
  return self;
}

-(void)dealloc
{
  if (_qso) [_qso release];
  if (_bt) [_bt release];
  [super dealloc];
}

-(NSString*)QSO
{
  NSString* btStr = [NSString stringWithFormat:@"%@\n", _bt];
  [_qso replaceOccurrencesOfString:@".\n" withString:btStr
        options:NSLiteralSearch range:NSMakeRange(0, [_qso length])];
  return [NSString stringWithString:_qso];
}
@end

/*
 *************************************
 * Routines to put sentences/clauses *
 *************************************
  */
@implementation QSO (Private)
-(void)putMisc
{
  NSString* misc = Choose(@"Misc");
  if (misc && [misc length])
  {
    [_qso appendFormat:@"%@%s\n", misc, ([misc characterAtIndex:[misc length]-1]=='?')? "":"."];
  }
}

-(void)putThanks
{
  switch (Roll (6))
  {
    case 2:
    [_qso appendFormat:@"thanks for your call.\n"];
    break;

    case 3:
    [_qso appendFormat:@"tnx for ur call.\n"];
    break;

    case 4:
    [_qso appendFormat:@"tnx for the call.\n"];
    break;

    case 5:
   [_qso appendFormat:@"thanks for the call.\n"];
    break;

    default:
    [_qso appendFormat:@"thanks %@ for the call.\n", Choose(@"Name")];
    break;
  }
}

-(void)putName
{
  switch (Roll (6))
  {
    case 2:
    [_qso appendFormat:@"name is %@.\n", Choose(@"Name")];
    break;

    case 4:
    [_qso appendFormat:@"this is %@.\n", Choose(@"Name")];
    break;

    case 5:
    [_qso appendFormat:@"%@ here.\n", Choose(@"Name")];
    break;

    default:
    [_qso appendFormat:@"my name is %@.\n", Choose(@"Name")];
    break;
  }
}

-(void)putJob
{
  if (_age > 17)
  {
    switch (Roll (20))
    {
      case 2:
      case 3:
      [_qso appendFormat:@"my occupation is %@.\n", Choose(@"Job")];
      break;

      case 4:
      case 5:
      [_qso appendFormat:@"i work as %@.\n", A_Or_An(Choose(@"Job"))];
      break;

      case 6:
      [_qso appendFormat:@"i was %@, now unemployed.\n", A_Or_An(Choose(@"Job"))];
      break;

      case 11:
      [_qso appendFormat:@"occupation %@.\n", Choose(@"Job")];
      break;
      
      case 12:
      [_qso appendFormat:@"occupation is %@.\n", Choose(@"Job")];
      break;

      default:
      [_qso appendFormat:@"i am %@.\n", A_Or_An(Choose(@"Job"))];
      break;
    }
  }
}

-(void)putAge
{
  switch (Roll (5))
  {
    case 3:
    [_qso appendFormat:@"my age is %d.\n", _age];
    break;

    case 4:
    [_qso appendFormat:@"i am %d years old.\n", _age];
    break;

    default:
    [_qso appendFormat:@"age is %d.\n", _age];
    break;
  }
}

-(void)putLicense
{
  int years = Roll([self licenseSeed]) + 1;
  switch (Roll (13))
  {
    case 1:
    [_qso appendFormat:@"i have %@ class licence.\n",
      A_Or_An(Choose(@"License"))];
    break;

    case 2:
    [_qso appendFormat:@"i am %@ license ham.\n",
      A_Or_An(Choose(@"License"))];
    break;

    case 3:
    [_qso appendFormat:@"i am %@ licence ham.\n",
      A_Or_An(Choose(@"License"))];
    break;

    case 4:
    [_qso appendFormat:@"i have been licenced %d year%s as %@ class.\n",
      years, (years==1)? "":"s", Choose(@"License")];
    break;

    case 5:
    [_qso appendFormat:@"i have %@ class license.\n",
      A_Or_An(Choose(@"License"))];
    break;

    case 6:
    [_qso appendFormat:@"i am %@ class ham.\n",
      A_Or_An(Choose(@"License"))];
    break;

    case 7:
    [_qso appendFormat:@"i have been licensed %d year%s as %@ class.\n",
      years, (years==1)? "":"s", Choose(@"License")];
    break;
    
    case 8:
    [_qso appendFormat:@"just got my %@ license.\n",
      Choose(@"License")];
    break;

    default:
    [_qso appendFormat:@"i have been %@ class ham for %d year%s.\n",
      A_Or_An(Choose(@"License")), years, (years==1)? "":"s"];
    break;
  }
}

-(void)putTemperature
{
  [_qso appendFormat:@"temperature is %d.\n", Roll (80) + 10];
}

-(void)putWeather1
{
  switch (Roll (17))
  {
    case 2:
    [_qso appendFormat:@"wx is %@.\n", Choose(@"Weather1")];
    [self putTemperature];
    break;

    case 3:
    [_qso appendFormat:@"weather here is %@.\n", Choose(@"Weather1")];
    break;

    case 4:
    [_qso appendFormat:@"weather is %@.\n", Choose(@"Weather1")];
    break;

    case 5:
    [_qso appendFormat:@"wx is %@.\n", Choose(@"Weather1")];
    break;

    case 6:
    [self putTemperature];
    [_qso appendFormat:@"weather here is %@.\n", Choose(@"Weather1")];
    break;

    case 7:
    [self putTemperature];
    [_qso appendFormat:@"weather is %@.\n", Choose(@"Weather1")];
    break;

    case 8:
    [self putTemperature];
    [_qso appendFormat:@"wx is %@.\n", Choose(@"Weather1")];
    break;

    case 9:
    [_qso appendFormat:@"weather here is %@ and temperature is %d.\n",
      Choose(@"Weather1"), Roll (80) + 10];
    break;

    case 10:
    [_qso appendFormat:@"weather is %@, temperature %d.\n",
      Choose(@"Weather1"), Roll (80) + 10];
    break;

    case 11:
    [_qso appendFormat:@"wx is %d degrees and %@.\n",
      Roll(80) + 10, Choose(@"Weather1")];
    break;

    case 12:
    [_qso appendFormat:@"The wx is %@ and the temp is %d degrees.\n",
      Choose(@"Weather1"), Roll (80) + 10];
    break;

    case 14:
    [_qso appendFormat:@"weather is %@.\n", Choose(@"Weather1")];
    [self putTemperature];
    break;

    case 15:
    [_qso appendFormat:@"weather here is %@.\n", Choose(@"Weather1")];
    [self putTemperature];
    break;

    default:
    [_qso appendFormat:@"wx is %@ and %d degrees.\n",
      Choose(@"Weather1"), Roll (80) + 10];
  }
}

-(void)putWeather2
{
  switch (Roll (10))
  {
    case 0:
    [_qso appendFormat:@"it is %@.\n", Choose(@"Weather2")];
    break;

    case 1:
    [_qso appendFormat:@"it is %@ and %d degrees.\n",
      Choose(@"Weather2"), Roll (80) + 10];
    break;

    case 2:
    [_qso appendFormat:@"the WX is %@ and the temp is %d degrees.\n",
      Choose(@"Weather2"), Roll (80) + 10];
    break;

    case 3:
    [_qso appendFormat:@"wx is %@ and the temp is %d degrees.\n",
      Choose(@"Weather2"), Roll (80) + 10];
    break;

    case 4:
    [_qso appendFormat:@"it is %@ today.\n", Choose(@"Weather2")];
    break;

    case 5:
    [_qso appendFormat:@"it is %@ and %d degrees.\n",
      Choose(@"Weather2"), Roll (100) + 3];
    break;

    case 6:
    [_qso appendFormat:@"the wx is %@ and the temp is %d degrees.\n",
      Choose(@"Weather2"), Roll (90) + 10];
    break;

    case 7:
    [_qso appendFormat:@"wx is %@ and the temp is %d degrees.\n",
      Choose(@"Weather2"), Roll (80) + 10];
    break;

    default:
    [_qso appendFormat:@"it is %@ here.\n", Choose(@"Weather2")];
    break;
  }
}

-(void)putWeather
{
  switch (Roll(4))
  {
    case 3:
    [self putWeather1];
    break;

    default:
    [self putWeather2];
    break;
  }
}

-(void)putCityState
{
  switch (Roll (6))
  {
    case 4:
    [_qso appendFormat:@"%@ %@, ",
      Choose(@"Cityh"), Choose(@"Heights")];
    break;

    case 5:
    [_qso appendFormat:@"%@ %@, ", Choose(@"New"), Choose(@"Newcity")];
    break;

    default:
    [_qso appendFormat:@"%@, ", Choose(@"City")];
    break;
  }
  [_qso appendFormat:@"%@.\n", Choose(@"State")];
}

-(void)putLocation
{

  switch (Roll (5))
  {
    case 3:
    [_qso appendFormat:@"my qth is "];
    break;

    case 4:
    [_qso appendFormat:@"my location is "];
    break;

    default:
    [_qso appendFormat:@"qth is "];
    break;
  }
  [self putCityState];
}

-(void)putRig
{
  switch (Roll (19))
  {
    case 0:
    case 1:
    [_qso appendFormat:@"my rig runs %@ watts into %@ up %@ feet.\n",
      Choose(@"Power"), A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;

    case 2:
    case 3:
    [_qso appendFormat:@"rig is a %@ watt %@ and antenna is %@.\n",
      Choose(@"Power"), Choose(@"Rig"),
      A_Or_An(Choose(@"Antenna"))];
    break;

    case 4:
    case 5:
    [_qso appendFormat:@"my transceiver is %@.\n", A_Or_An(Choose(@"Rig"))];
    [_qso appendFormat:@"it runs %@ watts into %@.\n",
      Choose(@"Power"), A_Or_An(Choose(@"Antenna"))];
    break;

    case 6:
    case 7:
    [_qso appendFormat:@"the rig is %@ running %@ watts.\n",
      A_Or_An(Choose(@"Rig")), Choose(@"Power")];
    [_qso appendFormat:@"antenna is %@ up %@ m.\n",
      A_Or_An(Choose(@"Antenna")), Choose(@"Upfeet")];
    break;

    case 8:
    case 9:
    case 10:
    case 11:
    [_qso appendFormat:@"my rig runs %@ watts into %@ up %@ meters.\n",
      Choose(@"Power"), A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;

    case 12:
    [_qso appendFormat:@"my rig runs %@ watts into %@ up %@ feet, but the antenna has partly fallen.\n",
      Choose(@"Power"), A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;

    case 13:
    [_qso appendFormat:@"rig is %@ running %@ watts ",
      A_Or_An(Choose(@"Rig")), Choose(@"Power")];
    [_qso appendFormat:@"into %@ up %@ ft.\n",
      A_Or_An(Choose(@"Antenna")), Choose(@"Upfeet")];
    break;

    case 14:
    [_qso appendFormat:@"my rig runs %@ watts into %@ up %@ feet.\n",
      Choose(@"Power"), A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;

    case 15:
    [_qso appendFormat:@"rig is %@ watt %@ and antenna is %@.\n",
      A_Or_An(Choose(@"Power")),
      Choose(@"Rig"),
      Choose(@"Antenna")];
    break;

    case 16:
    [_qso appendFormat:@"my transceiver is %@.\n",
      A_Or_An(Choose(@"Rig"))];
    [_qso appendFormat:@"it runs %@ watts into %@.\n",
      Choose(@"Power"),
      A_Or_An(Choose(@"Antenna"))];
    break;

    case 17:
    [_qso appendFormat:@"the rig is %@ running %@ watts.\n",
      A_Or_An(Choose(@"Rig")),
      Choose(@"Power")];
    [_qso appendFormat:@"antenna is %@ up %@ feet.\n",
      A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;

    default:
    [_qso appendFormat:@"rig is %@ ", A_Or_An(Choose(@"Rig"))];
    [_qso appendFormat:@"running %@ watts into %@ up %@ feet.\n",
      Choose(@"Power"),
      A_Or_An(Choose(@"Antenna")),
      Choose(@"Upfeet")];
    break;
  }
}

-(void)putRST
{
  NSString* rst = Choose(@"RST");
  switch (Roll (8))
  {
    case 0:
    [_qso appendFormat:@"ur rst %@=%@.\n", rst, rst];
    break;

    case 1:
    [_qso appendFormat:@"rst is %@=%@.\n", rst, rst];
    break;

    case 2:
    [_qso appendFormat:@"rst %@=%@.\n", rst, rst];
    break;

    case 3:
    [_qso appendFormat:@"your rst %@=%@.\n", rst, rst];
    break;

    case 4:
    [_qso appendFormat:@"your RST is %@=%@.\n", rst, rst];
    break;

    case 5:
    [_qso appendFormat:@"your signal is rst %@/%@.\n", rst, rst];
    break;

    case 6:
    [_qso appendFormat:@"ur signal is rst %@,%@.\n", rst, rst];
    break;

    default:
    [_qso appendFormat:@"your rst is %@/%@.\n", rst, rst];
    break;
  }
}


-(void)putQFreq
{
  switch (Roll (8))
  {
    case 2:
    [_qso appendFormat:Choose(@"Frqmisc"), MakeFrequency(0, 0)];
    break;

    case 3:
    [_qso appendFormat:Choose(@"Callmisc"), Choose(@"Call")];
    break;

    case 4:
    [_qso appendFormat:Choose(@"Frqcallmisc"), Choose(@"Call"), MakeFrequency(0, 0)];
    break;

    case 5:
    [_qso appendFormat:Choose(@"Nummisc"), Roll(3) + Roll(2) + 1];
    break;

    default:
    return;
  }
  [_qso appendFormat:@"\n"];
}

-(void)putFirstCallsign
{
  _sender = Choose(@"Call");
  _receiver = Choose(@"Call");
  [_qso appendFormat:@"%@ de %@\n", _receiver, _sender];
}

-(void)putLastCallsign
{
  [_qso appendFormat:@"%@ de %@", _receiver, _sender];
}

-(int)licenseSeed
{
  if (_age > 20) return 20;
  if (_age < 10) return 10;
  return _age - 8;
}
@end

NSString* Choose(NSString* name)
{
  if (!gDict)
  {
    NSString* path = [[NSBundle mainBundle] pathForResource:@"QSO" ofType:@"plist"];
    gDict = [[NSDictionary alloc] initWithContentsOfFile:path];
  }
  NSArray* a = [gDict objectForKey:name];
  if (!a) NSLog(@"No array for %@", name);
  return [a objectAtIndex:Roll([a count])];
}

static NSString* A_Or_An(NSString* string)
{
  return [NSString stringWithFormat:@"%s %@",
         (is_vowel([string characterAtIndex:0]))? "an":"a", string];
}

static BOOL is_vowel(unichar first)
{
  return (
  first == 'A' ||
  first == 'E' ||
  first == 'I' ||
  first == 'O' ||
  first == 'U' ||
  first == 'a' ||
  first == 'e' ||
  first == 'i' ||
  first == 'o' ||
  first == 'u'
  );
}

int Roll(int Number)
{
  return arc4random() % Number;
}

int MakeFrequency(unsigned band, BOOL voice)
{
  if (!band) band = Roll(M6);
  unsigned base = (voice)? 7128:7000;
  unsigned range = (voice)? 172:100;
  switch (band)
  {
    case M160:
    base = 1800;
    range = 200;
    break;
    case M80:
    base = (voice)? 3604:3500;
    range = (voice)? 396:100;
    break;
    case M40:
    base = (voice)? 7129:7000;
    range = (voice)? 171:125;
    break;
    case M30:
    base = 10100;
    range = 50;
    break;
    case M20:
    base = (voice)? 14150:14000;
    range = (voice)? 196:150;
    break;
    case M17:
    base = (voice)? 18110:18068;
    range = (voice)? 54:42;
    break;
    case M15:
    base = (voice)? 21200:21000;
    range = (voice)? 246:200;
    break;
    case M12:
    base = (voice)? 24930:24890;
    range = (voice)? 56:40;
    break;
    case M10:
    base = (voice)? 28300:28000;
    range = (voice)? 1396:300;
    break;
    case M6:
    base = (voice)? 50100:50000;
    range = (voice)? 3896:4000;
    break;
    case M2:
    base = (voice)? 144100:144000;
    range = (voice)? 3896:4000;
    break;
  }
  return (base + Roll(range));
}


