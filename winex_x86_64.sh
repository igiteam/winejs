#!/bin/bash

pkill -9 -U $(whoami) wineserver wine wine64 wine-preloader wine64-preloader && pgrep -U $(whoami) -f ".exe" | xargs kill -9 2>/dev/null