# print(__doc__)

# Script to use scikit-learn for spectral co-clustering. Run this
# after generating the analysis datasets from experimental data

import sys
import argparse

parser = argparse.ArgumentParser(description='Run co-clustering from local database.')

# We expect about this many events from Pablo
parser.add_argument('--clusters', '-c', type=int, default=100,
                   help='number of clusters')

# Ignore events with too much stuff, no signal
parser.add_argument('--threshold', '-t', type=int, default=None,
                   help='threshold above which events are ignored')

# Whether to write the clusters back to the database
parser.add_argument('--write', '-w', action='store_const', const=True, default=False,
                   help='write results to db')

args = parser.parse_args()

skip_thresh = args.threshold
n_clusters = args.clusters

import numpy as np
from matplotlib import pyplot as plt
import pymongo
from pymongo import MongoClient

from sklearn.cluster.bicluster import SpectralCoclustering
# from sklearn.metrics import consensus_score

client = MongoClient('localhost', 3001)
db = client.meteor

events = db['analysis.events']
datastream = db['analysis.datastream']

identifier = "i%d_c%d" % (skip_thresh, n_clusters) if skip_thresh else "c%d" % (n_clusters)

# Build array of relationships between events and tweets

n_rows = datastream.find().count()
n_cols = events.find().count()
shape = (n_rows, n_cols)

# Should we really use float64 here?
data = np.ones(shape, dtype=np.float64) * 0.001

# Map tweets to a contiguous list, for now
data_list = list(datastream.find().sort('num', pymongo.ASCENDING))
events_list = list(events.find())

row_lookup = {}
for i, tweet in enumerate(data_list):
    row_lookup[tweet['num']] = i

for j, event in enumerate(events_list):
    sources = event['sources']    
    # Skip empty lists
    if not sources:
        continue
    
    # TODO hack: skip very long lists
    if skip_thresh and len(sources) > skip_thresh:
        continue

    # All events have numbered tweets
    rowSelector = np.array([row_lookup[source] for source in sources])
    data[rowSelector, j] = 1    

plt.matshow(data, cmap=plt.cm.Blues)
plt.title("Original dataset")

plt.savefig('%s_original.png' % (identifier), bbox_inches='tight')

model = SpectralCoclustering(n_clusters=n_clusters, random_state=0)
model.fit(data)

fit_data = data[np.argsort(model.row_labels_)]
fit_data = fit_data[:, np.argsort(model.column_labels_)]

plt.matshow(fit_data, cmap=plt.cm.Blues)
plt.title("After biclustering; rearranged")

plt.savefig('%s_clustered.png' % (identifier), bbox_inches='tight')

avg_data = np.copy(data)

# Compute average value in each co-cluster for display purposes
for c in range(n_clusters):
    for d in range(n_clusters):                       
        row_ind = np.nonzero(model.rows_[c])
        col_ind = np.nonzero(model.columns_[d])
        # print row_ind, col_ind

        row_sel = np.tile(row_ind, (col_ind[0].size, 1))
        col_sel = np.tile(col_ind, (row_ind[0].size, 1)).transpose()
        # print row_sel, col_sel
           
        avg_data[row_sel, col_sel] = np.average(data[row_sel, col_sel])

avg_data = avg_data[np.argsort(model.row_labels_)]
avg_data = avg_data[:, np.argsort(model.column_labels_)]

plt.matshow(avg_data, cmap=plt.cm.Blues)
plt.title("Average cluster intensity")

plt.savefig('%s_averaged.png' % (identifier), bbox_inches='tight')

if args.write:
    print "Writing clusters to database."
    # No need to clean up here, just overwrite by _id.
    for c in range(n_clusters):
        (nr, nc) = model.get_shape(c)
        (row_ind, col_ind) = model.get_indices(c)
        
        cluster_val = None
        if nr > 25 or nc > 50:
            print "Nulling cluster %d: shape (%d, %d)" % (c, nr, nc)
        else:
            cluster_val = c
            
        for ri in row_ind:
            data_list[ri]['cluster'] = cluster_val
            datastream.save(data_list[ri])
        for ci in col_ind:
            events_list[ci]['cluster'] = cluster_val
            events.save(events_list[ci])            

# plt.show()
