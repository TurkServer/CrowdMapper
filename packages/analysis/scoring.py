
# Script to score groups using a min-cost max-flow matching algorithm
# based on the ground truth created from clustering

import argparse

parser = argparse.ArgumentParser(description='Score groups using the gold standard.') 

parser.add_argument('goldStandardId', help='The world to use as the benchmark.')

parser.add_argument('--groupId', '-g', help='A specific group to run on. If unspecified, runs on all groups.')

parser.add_argument('--write', '-w', action='store_const', const=True, default=False,
                    help='Write results to database.')

args = parser.parse_args()

from munkres import Munkres, make_cost_matrix
from math import sqrt, log10
from pymongo import MongoClient

m = Munkres()

client = MongoClient('localhost', 3001)
db = client.meteor

events = db['events']
worlds = db['analysis.worlds']

world_list = list(
    worlds.find() if not args.groupId else worlds.find({_id: worlds.groupId}) )

gs_events = list( events.find({
           '_groupId': args.goldStandardId,
           'deleted': { '$exists': False },
           # Some events in gold standard don't have location:
           # They are just being used to hold data, so ignore them.
           'location': { '$exists': True }
            }) )

# Scoring function for an event. Current scheme is:
# 0.25 to type, 0.25 to region, 0.25 to province, 
# 0.25 for within 10km to 0 beyond 100km
def score(event, goldst):
    s = 0
    for field in ["type", "region", "province"]:
        if field in event and event[field] == goldst[field]:
            s += 0.25

    if "location" in event:
        dist_meters = 0.1 + sqrt(
            sum( (a - b)**2 for a, b in zip(event["location"], goldst["location"])))
        
        s += 0.25 * (1 - max(0, min(1, (log10(dist_meters) - 4))) )

    # Flip so it's a cost matrix
    return 1 - s

# 0.33 = up to 1 field wrong and ~20km away
# < 0.24 = just errors in the location

errorThresh = 0.33

for world in world_list:
    worldId = world["_id"]
    world_events = list( events.find({
                '_groupId': worldId,
                'deleted': { '$exists': False }
                }) )

    # Build matrix for Munkres
    mat = []
    for event in world_events:
        mat.append([score(event, gs) for gs in gs_events])

    partialCredit = sum([1 - mat[row][column] for row, column in m.compute(mat)])

    # Clamp matrix values for a threshold
    for row in mat:
        for j in range(len(row)):
            row[j] = 0 if row[j] < errorThresh else 1

    fullCredit = sum([1 - mat[row][column] for row, column in m.compute(mat)])

    print 'world %s, size %d, partial %.02f, full %.02f' % (
        worldId, world["nominalSize"], partialCredit, fullCredit)
                         
    if args.write:
        world["partialCreditScore"] = partialCredit
        world["fullCreditScore"] = fullCredit
        worlds.save(world)
