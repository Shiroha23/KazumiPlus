These tiny media fixtures were generated locally from FFmpeg's synthetic sources.
They contain no downloaded or third-party audiovisual content.

```
ffmpeg -f lavfi -i testsrc2=size=64x64:rate=10:duration=8 -an -c:v libx264 -pix_fmt yuv420p -g 10 -crf 35 -movflags +faststart video.mp4
ffmpeg -f lavfi -i sine=frequency=440:sample_rate=16000:duration=8 -vn -c:a aac -b:a 16k -movflags +faststart audio.m4a
```

The opt-in native playback test serves them on two local HTTP origins requiring
different headers. It checks stream loading, header isolation, seek/resume,
paused initialization, and audio failure handling with the bundled libmpv.
