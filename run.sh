#!/bin/zsh
# Loads API keys from ~/.config/murmr/env (if present) and starts murmr.
cd "${0:A:h}"
[ -f ~/.config/murmr/env ] && source ~/.config/murmr/env
exec ./murmr
