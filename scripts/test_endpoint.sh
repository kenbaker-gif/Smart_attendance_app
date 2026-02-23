#!/bin/bash
# Just a quick way to ping your backend
curl -f https://eloquent-renewal-production.up.railway.app/ > /dev/null \
  && echo "Railway is Up" || echo "Railway is Down"