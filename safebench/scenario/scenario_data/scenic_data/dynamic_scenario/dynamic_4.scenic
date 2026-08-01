'''The ego vehicle is driving on a straight road; the adversarial pedestrian suddenly appears from behind a parked car on the right front and suddenly stop.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > globalParameters.OPT_ADV_DISTANCE:
        wait
    take SetPositionAction(ego.position + (globalParameters.OPT_APPEAR_OFFSET perpendicular to ego.heading) + (globalParameters.OPT_APPEAR_DISTANCE forward from ego.position))
    take SetWalkingSpeedAction(0)

param OPT_ADV_DISTANCE = Range(0, 30)
param OPT_APPEAR_OFFSET = Range(-2, 2)  # lateral offset relative to ego's heading (meters)
param OPT_APPEAR_DISTANCE = Range(5, 15)  # distance ahead of ego where pedestrian appears (meters)
# Selecting a straight road segment (lane section with approximately zero curvature)
straightLaneSections = []
for lane in network.lanes:
    for laneSec in lane.sections:
        # In Scenic 2.1, we rely on geometric properties; `isStraight` is not available,
        # but we can use the fact that straight sections have no curvature —
        # CARLA's network exposes `curvature`, and Scenic 2.1 allows filtering on it.
        if abs(laneSec.curvature) < 0.001:
            straightLaneSections.append(laneSec)

if len(straightLaneSections) == 0:
    straightLaneSections = network.laneSections
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
Blocker = Car right of IntSpawnPt by globalParameters.OPT_GEO_BLOCKER_X_DISTANCE,
    with heading IntSpawnPt.heading,
    with regionContainedIn None
    
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Pedestrian at Blocker offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 90 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()