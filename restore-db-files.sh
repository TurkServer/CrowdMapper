#!/bin/bash
rm -rf .backups/cmdump
tar xjf $@
mongorestore --host localhost:3001 --dbpath .meteor/local/db --drop .backups/cmdump
