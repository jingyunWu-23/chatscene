'''The ego vehicle is driving on a straight road when a pedestrian suddenly crosses from the right front and suddenly stops as the ego vehicle approaches.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > globalParameters.OPT_ADV_DISTANCE:
        wait
    do CrossingBehavior(ego, globalParameters.OPT_ADV_SPEED, globalParameters.OPT_ADV_OFFSET) until (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    while True:
        take SetWalkingSpeedAction(0)

param OPT_ADV_SPEED = Range(0, 5)
param OPT_ADV_DISTANCE = Range(0, 15)
param OPT_ADV_OFFSET = Range(0, 15)
param OPT_STOP_DISTANCE = Range(0, 1)
# Selecting a straight lane section from the network
straightLaneSecs = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec.isStraight:
            straightLaneSecs.append(laneSec)

if len(straightLaneSecs) == 0:
    straightLaneSecs = network.laneSections
egoLaneSec = Uniform(*straightLaneSecs)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
param OPT_GEO_X_DISTANCE = Range(2, 8)
param OPT_GEO_Y_DISTANCE = Range(15, 50)

IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Pedestrian right of IntSpawnPt by globalParameters.OPT_GEO_X_DISTANCE,
    with heading IntSpawnPt.heading,  # Heading aligned with road (to step directly into path)
    with regionContainedIn None,
    with behavior AdvBehavior()