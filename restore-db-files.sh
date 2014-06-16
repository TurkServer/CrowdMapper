#!/bin/bash
rm -rf .backups/cmdump
tar xjf $@
mongorestore --dbpath .meteor/local/db --drop .backups/cmdump
