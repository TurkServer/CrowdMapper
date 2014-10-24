# RPC server using the method described at
# http://ianhinsdale.com/code/2013/12/08/communicating-between-nodejs-and-python/

import zerorpc
import logging

from munkres import Munkres

logging.basicConfig()

class AnalysisRPC(object):
    def __init__(self):
        self.m = Munkres()

    def hello(self, name):
        print "Hello called with: %s" % name
        return "Hello, %s" % name

    # mat is an nxm list of lists 
    # representing a weight matching matrix
    # satisfying 0 < mat(x,y) < 1
    def maxMatching(self, mat):
        result = self.m.compute(mat)
        return sum([1 - mat[row][column] for row, column in result])

s = zerorpc.Server(AnalysisRPC())
s.bind("tcp://127.0.0.1:4242")

print "Starting RPC server..."
s.run()
