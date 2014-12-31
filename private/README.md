# Description of files

- `PabloPh_UN_cm.csv`: filtered set of original data used by SBTF for Typhoon Pablo in 2012.

- `tutorial.csv`: small set of data used for the interactive tutorial.

- `fields-pablo.json`: configuration for the data entry fields used for the Pablo data.

- `seed-instructions.txt`: initial document loaded as instructions for groups working together.

- `groundtruth-pablo.json`: gold-standard set of events constructed from groups working together and corroborated with derived SBTF generated maps, found
[here](http://www.arcgis.com/home/webmap/viewer.html?webmap=1e606f1a7cf74a599ccec9d0d5893fb0&extent=115.1752,4.4788,133.5663,13.6042)
 and
[here](http://www.arcgis.com/home/webmap/viewer.html?webmap=fa64e3f0b09b4d61b0b907f8644cc272&extent=115.5322,4.5144,135.6152,16.1232).
Some "events" in this set do not have locations and represent data that may have been relevant but were not specific enough to tag. Only events that were tagged with a location were used for evaluation. Note also that many links may have broken since this dataset was generated, and as such it may be harder to verify; however, it was produced from a best effort using what was available at the time.
