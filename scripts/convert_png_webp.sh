#!/bin/bash
for file in *.png; do
    cwebp -lossless $file -o "${file%.*}.webp"
done