#!/bin/bash
set -e

# Install Flutter
git clone https://github.com/flutter/flutter.git --branch stable --depth 1 $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Enable web & get dependencies
flutter config --enable-web
flutter pub get

# Build
flutter build web --release
