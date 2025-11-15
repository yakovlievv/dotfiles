#!/usr/bin/env bash

rm -rf ~/bin
ln -s "${HOME}/dots/bin" "${HOME}/bin"
export PATH="$PATH:$HOME/bin"
