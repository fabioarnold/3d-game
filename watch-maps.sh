#!/bin/bash

# install nodemon using `npm install -g nodemon`
nodemon -w Content/Maps -i Content/Maps/autosave -x "zig build" -e ".map"
