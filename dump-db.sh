#!/bin/bash
rm -rf cmdump
mongodump --host localhost:3002 -o cmdump
tar cjvf cmdump.tar.bz2 cmdump/
