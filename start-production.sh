#!/bin/bash
export HTTP_FORWARDED_COUNT=1
# Don't listen on public interface of port 3000.
meteor --port=localhost:3000 --settings settings-private.json --production
