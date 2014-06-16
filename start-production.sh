#!/bin/bash
export HTTP_FORWARDED_COUNT=1
meteor --settings settings-private.json --production
