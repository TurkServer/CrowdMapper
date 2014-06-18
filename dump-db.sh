#!/bin/bash
rm -rf .backups/cmdump
mongodump --host localhost:3001 -o .backups/cmdump
tar cjvf .backups/cmdump.tar.bz2 .backups/cmdump/
