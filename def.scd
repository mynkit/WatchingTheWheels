Server.killAll;

// 出力先デバイスの確認
ServerOptions.inDevices;
ServerOptions.outDevices;

// 出力先変更
(
Server.default.options.inDevice_(ServerOptions.inDevices[0]);
Server.default.options.outDevice_(ServerOptions.outDevices[0]);
Server.default.reboot;
SuperDirt.start;
)

(
Server.default.options.inDevice_(ServerOptions.inDevices[0]);
Server.default.options.outDevice_("Soundflower (2ch)");
Server.default.reboot;
SuperDirt.start;
)

// シンセやエフェクトの定義
(
var decoder = FoaDecoderMatrix.newStereo((100).degrad, (3-sqrt(3))/2);

~dirt.addModule('HRTF', { |dirtEvent|
	dirtEvent.sendSynth('HRTF' ++ ~dirt.numChannels,
		[
			theta: ~theta,
			phi: ~phi,
			out: ~out
		]
	)
}, { ~theta.notNil or: { ~phi.notNil }});
SynthDef("HRTF" ++ ~dirt.numChannels, { |out, theta, phi|
	var signal, in, left, right, foa;
	in = In.ar(out, ~dirt.numChannels);
	left = in[0];
	right = in[1];
	in = [(left+right), (left+right)];
	// theta is our angle on the X-Y plane and phi is our elevation
	theta = (theta-1) * pi;
	phi = phi * (-pi/2);
	// Encode into our foa signal
    foa = FoaPanB.ar(in, theta, phi);
	// decode our signal using our decoder defined above
    signal = FoaDecode.ar(foa, decoder);
	ReplaceOut.ar(out, signal)
}, [\ir]).add;

~dirt.loadSoundFiles(thisProcess.nowExecutingPath.dirname ++ "/samples/*");

~dirt.orbits.do { |x|
	x.globalEffects = [
		GlobalDirtEffect(\dirt_delay, [\delaytime, \delayfeedback, \delaySend, \delayAmp, \lock, \cps]),
		GlobalDirtEffect(\pingpong_delay, [\pingpongt, \pingpongfb, \pingpong, \cps]),
		GlobalDirtEffect(\dirt_reverb, [\size, \room, \dry]),
		GlobalDirtEffect(\schroeder_reverb, [\scReverb, \ice]),
		GlobalDirtEffect(\freeverb, [\size, \freeverb, \damp]),
		GlobalDirtEffect(\dirt_leslie, [\leslie, \lrate, \lsize]),
		GlobalDirtEffect(\dirt_rms, [\rmsReplyRate, \rmsPeakLag]).alwaysRun_(true),
		GlobalDirtEffect(\dirt_monitor, [\limitertype]).alwaysRun_(true)
	]
};

SynthDef("pingpong_delay" ++ ~dirt.numChannels, { |dryBus, effectBus, gate = 1, pingpongt, pingpongfb, pingpong, cps = 1|
	var signal = In.ar(dryBus, ~dirt.numChannels);
	var maxDelayTime = 4;
	var delaytime, delayfeedback, delayAmp, decayTime, left, right, dry, pingponglpf=1000;

	delayAmp = pingpong;
	delaytime = pingpongt;
	delayfeedback = pingpongfb;

	delayfeedback = delayfeedback.clip(0, 0.99);
	delaytime = delaytime * reciprocal(cps);
	delaytime = delaytime.clip(0, maxDelayTime); // just to be sure
	decayTime = log2(-60.dbamp) / log2(delayfeedback) * delaytime;
	decayTime = decayTime.clip(0, 20);

	dry = signal;
	right = CombL.ar(dry, maxDelayTime*2, delaytime.lag(0.05)*2, decayTime);
	right = LPF.ar(right, pingponglpf);
	left = DelayN.ar(dry + right, maxDelayTime, delaytime.lag(0.05));
	signal = NumChannels.ar([dry, dry] + [left*delayAmp, right*delayAmp], ~dirt.numChannels);

	signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);

	DirtPause.ar(signal, graceTime:4);

	Out.ar(effectBus, signal);
}, [\ir, \ir]).add;

SynthDef("schroeder_reverb" ++ ~dirt.numChannels, { |dryBus, effectBus, gate = 1, scReverb, ice|
	var signal = In.ar(dryBus, ~dirt.numChannels);
	var chain, in, z, y, oct;

	z = DelayN.ar(signal, 0.048);
	y = Mix.ar(Array.fill(7,{ CombL.ar(z, 0.1, 1, 15) }));
	// 32.do({ y = AllpassN.ar(y, 0.050, [0.050.rand, 0.050.rand], 1) });
	32.do({ y = AllpassN.ar(y, 0.02, [0.02.rand, 0.02.rand], 1) });
	oct = 1.0 * LeakDC.ar( abs(y) );
	y = SelectX.ar(ice, [y, ice * oct, DC.ar(0)]);
	signal = signal + (0.2*y*scReverb);

	signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);

	DirtPause.ar(signal, graceTime:4);

	Out.ar(effectBus, signal);
}, [\ir, \ir]).add;

SynthDef("freeverb" ++ ~dirt.numChannels, { |dryBus, effectBus, gate = 1, size, freeverb, damp|
	var signal = In.ar(dryBus, ~dirt.numChannels);
	var y;

	y = FreeVerb.ar(signal, 1, size, damp);

	signal = signal + (y * freeverb);

	DirtPause.ar(signal, graceTime:4);

	Out.ar(effectBus, signal);
}, [\ir, \ir]).add;

Server.default.freeAll;

SynthDef("SinOscSynthBend", {
	arg out, sustain=1, decay=0, pan=0, freq=110, accelerate=0, slide=0, sustainpedal=0.5, vibratoFreq=10, vibratoDepth=0;
	var fglide, detune, sound, sig1, sig2, env, bendSustain;
	bendSustain = sustainpedal;
	// detune = 1.001;
	detune = 1.0;
	fglide = EnvGen.ar(Env.perc(0.05, 0.3, 1, \lin), timeScale:bendSustain) * (-1*slide/4) + 1;
	freq = freq * fglide * Line.kr(1, 1+accelerate, bendSustain);
	freq = freq *(1+((LFPar.ar(vibratoFreq)+1)*(vibratoDepth/50)));
	sig1 = SinOsc.ar(freq).dup;
	sig2 = SinOsc.ar(freq * detune).dup;
	sound = (sig1 + sig2) * 0.5;
	env = EnvGen.ar(Env.linen(0.01, 0, 0.6, 1, -3), timeScale:sustain, doneAction:2);
	//env = EnvGen.ar(Env.pairs([[0,0],[0.03,1],[0.2,1-decay],[0.95,1-decay],[1,0]], -1), timeScale:sustain, doneAction:2);
	OffsetOut.ar(out, DirtPan.ar(sound, ~dirt.numChannels, pan, env));
}).add;

SynthDef("FastSinSynth", {
	arg out, sustain=1, decay=0, pan=0, freq=110, accelerate=0, vibratoFreq=10, vibratoDepth=0;
	var fglide, detune, sound, sig1, sig2, env, parFreq;
	detune = 1.0;
	freq = freq *(1+((LFPar.ar(vibratoFreq)+1)*(vibratoDepth/50)));
	sig1 = SinOsc.ar(freq).dup;
	sig2 = SinOsc.ar(freq * detune).dup * 0.1;
	sound = (sig1 + sig2) * 0.5;
	parFreq = 0.8 + EnvGen.ar(Env.linen(0, 0, 0.6, 10, -7), timeScale:sustain);
	// pan = EnvGen.ar(Env.linen(0, 0, 0.6, (pan), 1), timeScale:sustain); // pan slide
	// sound = sound*LFPar.kr(parFreq); // tremoro
	// panning
	sound = Pan2.ar(sound, FSinOsc.kr(1.43));
	env = EnvGen.ar(Env.linen(0, 0, 0.6, 1, -2), timeScale:sustain, doneAction:2);
	OffsetOut.ar(out, DirtPan.ar(sound, ~dirt.numChannels, pan, env));
}).add;

SynthDef("superhammondBend", {
	arg out, sustain=1, decay=0, pan, freq, vibrato=0.5, vrate=7, voice=0, perc=0, percf=2, accelerate=0, slide=0, sustainpedal=0.5;
	var freqs, amps, sound, click, env, ampscale, attrel, fglide, bendSustain;
	bendSustain = sustainpedal;
	// attrel = (sustain/2).clip(0,0.005);
	// env = EnvGen.ar(Env.linen(attrel, sustain-(2*attrel), attrel), doneAction:2);
	env = EnvGen.ar(Env.linen(0.1, sustain, 0.1, sustain), doneAction:2);
	fglide = EnvGen.ar(Env.perc(0.05, 0.3, 1, \lin), timeScale:bendSustain) * (-1*slide/4) + 1;
	freq = freq * fglide * Line.kr(1, 1+accelerate, bendSustain);
	freqs = [0.5, 1.4988, 1, 2, 2.9976, 4, 5.0409, 5.9953, 8, 1.001] * freq;
	freqs = 2**(freqs < 63) * freqs; // fold up bottom register
	freqs = freqs / (2**(freqs > 6000)); // fold down high harmonics
	freqs = freqs / (2**(freqs > 6000)); // do it again for the really high notes
	amps = SelectX.kr(voice, #[
		[1, 4, 5, 4, 3, 1, 0, 0, 0], // 0: bass violin 16'
		[0, 0, 8, 0, 4, 0, 0, 0, 0], // 1: tibia 8'
		[0, 7, 8, 1, 2, 0, 0, 0, 0], // 2: bassoon 8'
		[0, 0, 7, 8, 8, 8, 8, 7, 2], // 3: french trumpet 8'
		[4, 0, 5, 5, 4, 5, 3, 3, 6], // 4: string ensemble
		[8, 8, 5, 3, 2, 4, 5, 8, 8], // 5: Blues
		[8, 8, 8, 0 ,0, 0, 0, 0, 3], // 6: Jazz 1
		[8, 8, 8, 8, 8, 8, 8, 8, 8], // 7: Full Shout
		[8, 0, 0, 0, 0, 0, 8, 8, 8], // 8: Bro' Jack
		[0, 0, 8, 8, 0, 0, 0, 0, 0]  // 9: Jazz 2
	]);
	amps = amps - [0, 0, 0, 0, 0, 0, 0.5, 1, 1.5]; // damp brilliance a bit
	amps = 2**(amps-8);
	click = WhiteNoise.ar(1) * XLine.ar(1,1e-6, 0.1);
	sound = 0.5 * Mix.ar( SinOsc.ar(freqs, (2pi ! 9).rand, amps/amps.sum) );
	// オルガンサウンド特有のアタック音が欲しい場合
	//sound = 0.5 * Mix.ar( SinOsc.ar(freqs*(2*click+1), (2pi ! 9).rand, amps/amps.sum) );
	sound = perc * 0.5 * SinOsc.ar(freq*percf, 2pi.rand) * XLine.ar(1,1e-6,2*decay+1) + sound;
	sound = sound + BAllPass.ar(sound, 1000*LFTri.kr(vrate,0,vibrato/2,1));
	// panning
	sound = Pan2.ar(sound, FSinOsc.kr(1.43));
	Out.ar(out, DirtPan.ar(sound, ~dirt.numChannels, pan, env));
}).add;

SynthDef("bassSynth", {
	arg out, sustain=1, decay=0, pan, freq, vibrato=0.5, vrate=7, voice=0, perc=0, percf=2, accelerate=0, slide=0, sustainpedal=0.5;
	var freqs, amps, sound, click, env, ampscale, attrel, fglide, bendSustain;
	bendSustain = sustainpedal;
	attrel = (sustain/2).clip(0,0.005);
	env = EnvGen.ar(Env.linen(0, 0, 0.6, 1, 6), timeScale:sustain, doneAction:2);
	fglide = EnvGen.ar(Env.perc(0.05, 0.3, 1, \lin), timeScale:bendSustain) * (-1*slide/4) + 1;
	freq = freq * fglide * Line.kr(1, 1+accelerate, bendSustain);
	freqs = [0.5, 1.4988, 1, 2, 2.9976, 4, 5.0409, 5.9953, 8, 1.001] * freq;
	freqs = 2**(freqs < 63) * freqs; // fold up bottom register
	freqs = freqs / (2**(freqs > 6000)); // fold down high harmonics
	freqs = freqs / (2**(freqs > 6000)); // do it again for the really high notes
	amps = SelectX.kr(voice, #[
		[1, 4, 5, 4, 3, 1, 0, 0, 0], // 0: bass violin 16'
	]);
	amps = amps - [0, 0, 0, 0, 0, 0, 0.5, 1, 1.5]; // damp brilliance a bit
	amps = 2**(amps-8);
	click = WhiteNoise.ar(1) * XLine.ar(1,1e-6, 0.1);
	sound = 0.5 * Mix.ar( SinOsc.ar(freqs, (2pi ! 9).rand, amps/amps.sum) );
	// sound = perc * 0.5 * SinOsc.ar(freq*percf, 2pi.rand) * XLine.ar(1,1e-6,2*decay+1) + sound;
	// sound = sound + BAllPass.ar(sound, 1000*LFTri.kr(vrate,0,vibrato/2,1));
	// panning
	// sound = Pan2.ar(sound, FSinOsc.kr(1.43));
	Out.ar(out, DirtPan.ar(sound, ~dirt.numChannels, pan, env));
}).add;

SynthDef("MyMoog", {
	arg out, freq = 110, sustain = 1, pan = 0.5, pitch1=4.0, accelerate=0, slide=0, sustainpedal=0.5;
	var detune, sig1, sig2, env, sound, fglide, bendSustain;
	bendSustain = sustainpedal;
	fglide = EnvGen.ar(Env.perc(0.05, 0.3, 1, \lin), timeScale:bendSustain) * (-1*slide/4) + 1;
	freq = freq * fglide * Line.kr(1, 1+accelerate, bendSustain);
	detune = 1.005;
	sig1 = MoogFF.ar(
		Pulse.ar(freq, LFNoise1.ar(1.0,0.3,0.4)),
		freq*pitch1, 3
	).dup;
	sig2 = MoogFF.ar(
		Pulse.ar(freq, LFNoise1.ar(1.0,0.2,0.4)),
		freq*pitch1*1.5, 3
	).dup;
	sound = (sig1 + sig2) * 1;
	env = EnvGen.ar(Env.linen(0.001, 0, 0.6, 1, -5), timeScale:sustain, doneAction:2);
	OffsetOut.ar(out, DirtPan.ar(sound, ~dirt.numChannels, pan, env));
}).add;

SynthDef(\zure, {|out, sustain=1, pan, accelerate, freq, decay=0, slide=1, detune=1 |
	// var env = EnvGen.ar(Env.linen(0.0001, 0, 0.6, 1, -3), timeScale:sustain, doneAction:2);
	var env = EnvGen.ar(Env.linen(0, 0, 0.6, 1, -2), timeScale:sustain, doneAction:2);
	var basefreq = freq * Line.kr(1, 1+accelerate, sustain);
	var sound = VarSaw.ar(basefreq, 0, Line.ar(0,0.5,sustain*20/slide));
	var sound2 = VarSaw.ar(basefreq*(detune/100+1), 0, Line.ar(0,0.5,sustain*20/slide));
	var sound3 = VarSaw.ar(basefreq*(-1*detune/100+1), 0, Line.ar(0,0.5,sustain*20/slide));
	var lpfEnv = 400 + EnvGen.ar(Env.linen(0, 0, 0.5, 2000, -30), timeScale:sustain);
	sound = sound - DelayN.ar(sound2,0.2, Line.ar(0,1,5*sustain/slide)/basefreq)
	+ DelayN.ar(sound3,0.2, Line.ar(0,1,20*sustain/slide)/basefreq);
	sound = LPF.ar(sound, lpfEnv);
	Out.ar(out, DirtPan.ar(sound/2, ~dirt.numChannels, pan, env));
}).add

)
