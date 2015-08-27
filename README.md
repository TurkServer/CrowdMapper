CrowdMapper
===========

Real-time collaborative application for tagging streams of geospatial data, built on top of the Meteor Javascript platform. Built with the humanitarian goal of crisis mapping in mind.

[![CrowdMapper Replay](http://share.gifyoutube.com/mLnMWR.gif)](https://www.youtube.com/watch?v=xJYq_kh6NlI)

This project uses [TurkServer](https://github.com/HarvardEconCS/turkserver-meteor) to study how people can organize to do crisis mapping. It was used to run the experiment and generate the data for the following paper:

> [Mao A, Mason W, Suri S, Watts DJ (2016) An Experimental Study of Team Size and Performance on a Complex Task. PLoS ONE 11(4): e0153048.][cm-plos]

[cm-plos]: http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0153048

## Running the app

[Install Meteor]. Then, clone this repository and run the following command:

```
meteor --settings settings.json
```

If that works, then you should be able to view the data from the experiment. Using this software to run another experiment is a bit more complicated, as it's not that well documented. However, the code is well-commented.

[install meteor]: https://www.meteor.com/install

## Viewing the data

CrowdMapper was designed to both facilitate a teamwork task as well as log the interactions for further analysis. Using the data from the experiment, you can access visualizations and replays with the following instructions:

1. Start Meteor in development mode as above.
2. Unzip the MongoDB dump to a local directory, e.g. `tar xjvf data.tar.bz2`. Usually, you want to make sure this is in a folder preceded by `.` so that Meteor doesn't try to read it, e.g. `.backups/data`.
3. Replace the database `mongorestore --host localhost:3001 --drop .backups/data`. Once this finishes, you will have a copy of the database from after the experiment.
4. You will need to restart Meteor to reset the admin password. Then, you can access the visualizations and replays at http://127.0.0.1:3000/overview.

To do further analysis on the data, please consult the instructions below, and the source code.

## Additional dependencies

If you are replicating the original analysis from the paper, this project has several dependencies that can't be installed by Meteor.

The data analysis uses [libzmq](https://github.com/zeromq/libzmq) for Node.js to make RPC calls to algorithms implemented in Python, as outlined in [this blog post](http://ianhinsdale.com/code/2013/12/08/communicating-between-nodejs-and-python/). If you don't have ZeroMQ installed on your system, you will see an error when starting the Meteor app (it should still start) and you won't be able to start the Python computation process or run any of the data analysis methods.
       
To make the analysis algorithms available, first install the `libzmq` and `libevent` libraries, using whatever is appropriate for your system. For example, on Ubuntu:
       
```
apt-get install libzmq-dev
apt-get install libevent
```

If all the above works, Meteor should be able to install the `zerorpc` npm package as part of the app without any issues.

In addition, install the python dependencies for ZeroRPC, and Munkres (the Hungarian algorithm):
       
```
pip install pyzmq
pip install zerorpc
pip install munkres
```       
