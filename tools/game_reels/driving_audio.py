"""Quiet deterministic engine and tyre layers, only while the cars move."""
import json
from pathlib import Path
import numpy as np
from tools.signs_reel import audio,config as C
import sys
out=Path(sys.argv[1]).resolve()
m=json.loads((out/'timeline.json').read_text())
rng=np.random.default_rng(20)
def roll(duration,gain,kind='car'):
 n=round(duration*C.SR);t=np.arange(n)/C.SR
 # Harmonic engine with a brief acceleration, soft low-passed tyre noise.
 rpm=62+26*(1-np.exp(-t*2))
 phase=2*np.pi*np.cumsum(rpm)/C.SR
 engine=np.sin(phase)+.28*np.sin(2*phase)+.12*np.sin(3*phase)
 noise=rng.normal(0,1,n);freq=np.fft.rfftfreq(n,1/C.SR)
 noise=np.fft.irfft(np.fft.rfft(noise)/(1+(freq/480)**4),n)
 noise/=max(np.std(noise),.001)
 env=np.minimum(np.clip(t/.18,0,1),np.clip((duration-t)/.45,0,1))
 if kind=='tram':
  # Softer electric hum and regular subdued wheel/rail joints.
  engine=.45*np.sin(phase*.65)+.12*np.sin(phase*2.1)
  joints=np.exp(-((t%.48)/.025)**2)*noise*.18
  signal=engine+.32*noise+joints
 else:signal=engine+.22*noise
 return (signal*env*gain).astype(np.float32)
motion=m['episode']['motion']
tracks=[(0,audio.read_wav(out/'sound.wav')),
 (m['reveal']+motion['playerDelay'],roll(motion['playerDuration'],.022)),
 (m['reveal']+motion['npcDelay'],roll(motion['npcDuration'],.014,motion.get('npcSound','car')))]
audio.write_wav(out/'sound-driving.wav',audio.mix(tracks,m['duration']))
print('Quiet driving layers mixed, original speech unchanged')
