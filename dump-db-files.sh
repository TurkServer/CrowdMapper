#!/bin/bash
rm -rf .backups/cmdump
mongodump --dbpath .meteor/local/db -o .backups/cmdump
tar cjvf .backups/cmdump.tar.bz2 .backups/cmdump/
