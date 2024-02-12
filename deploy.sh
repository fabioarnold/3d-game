#!/bin/bash
zig build -Doptimize=ReleaseSmall
scp -r index.html js style.css zig-out fabioarnold.de:/var/www/fabioarnold.de/games/celeste64/
