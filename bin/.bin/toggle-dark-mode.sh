#!/bin/sh

osascript -e 'tell app "System Events" to tell appearance preferences to return dark mode' > /tmp/is_dark_mode
