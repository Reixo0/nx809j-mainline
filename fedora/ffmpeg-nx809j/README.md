# FFmpeg V4L2 decoder fix

`0001-*.patch` applies to FFmpeg n9.0.2 (libavcodec only, distro independent).
It makes hardware decoding through `h264_v4l2m2m` (and the other `*_v4l2m2m`
decoders) survive seeks: without it the iris decoder returns stale frames after
a mid-stream seek and nothing after a seek from the end (looping, replay).

Not packaged yet: it goes into the FFmpeg package of the distro the image moves
to (Fedora: add it to the ffmpeg spec).

`seektest.c` checks it: decode, seek back after N frames, decode to the end,
seek again after EOF, and print an md5 per frame.

    gcc -O2 -o seektest seektest.c $(pkg-config --cflags --libs libavcodec libavformat libavutil)
    ./seektest clip.mp4 h264_v4l2m2m 100 1 > seek.txt
    ./seektest clip.mp4 h264_v4l2m2m 100000 0 > clean.txt   # no seek

Each pass must give every frame, and passes 2 and 3 must match `clean.txt`.
