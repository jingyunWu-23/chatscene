'''The ego vehicle is driving on a straight road; the adversarial pedestrian stands behind a bus stop on the right front, then suddenly sprints out onto the road in front of the ego vehicle and stops.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > globalParameters.OPT_ADV_DISTANCE:
        wait
    do CrossingBehavior(ego, globalParameters.OPT_ADV_SPEED, 0) until (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    take SetWalkingSpeedAction(0)

param OPT_ADV_SPEED = Range(3, 7)
param OPT_ADV_DISTANCE = Range(5, 25)
param OPT_STOP_DISTANCE = Range(0, 1)
# Selecting a straight road segment (lane section with negligible curvature)
straightLaneSections = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec.curvature < 0.001:  # Approximate straightness
            straightLaneSections.append(laneSec)

egoLaneSec = Uniform(*straightLaneSections)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
param OPT_GEO_BLOCKER_X_DISTANCE = Range(2, 8)
param OPT_GEO_BLOCKER_Y_DISTANCE = Range(15, 50)
param OPT_GEO_X_DISTANCE = Range(-2, 2)
param OPT_GEO_Y_DISTANCE = Range(2, 6)

IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_BLOCKER_Y_DISTANCE
Blocker = BusStop right of IntSpawnPt by globalParameters.OPT_GEO_BLOCKER_X_DISTANCE,
    with heading IntSpawnPt.heading,
    with regionContainedIn None
    
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Pedestrian at Blocker offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 90 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()