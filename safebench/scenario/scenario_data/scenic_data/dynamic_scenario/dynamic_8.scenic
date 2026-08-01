'''The ego vehicle is turning right at an intersection; the adversarial pedestrian on the left front suddenly crosses the road and stops in the middle of the intersection, blocking the ego vehicle's path.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    do CrossingBehavior(ego, globalParameters.OPT_ADV_SPEED, globalParameters.OPT_ADV_DISTANCE) until (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    while True:
        take SetWalkingSpeedAction(0)

param OPT_ADV_SPEED = Range(0, 5)
param OPT_ADV_DISTANCE = Range(0, 15)
param OPT_STOP_DISTANCE = Range(0, 1)
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
if egoInitLane is None:
    egoInitLane = Uniform(*network.laneSections)
require egoInitLane is not None
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
param OPT_GEO_X_DISTANCE = Range(-8, -2)  # Offset leftward from centerline (sidewalk/crosswalk side)
param OPT_GEO_Y_DISTANCE = Range(-5, 15)   # Forward along centerline, covering zebra crossing / intersection approach

EgoManeuverEndLane = egoManeuver.endLane
if EgoManeuverEndLane is None:
    EgoManeuverEndLane = Uniform(*network.laneSections)
require EgoManeuverEndLane is not None
IntSpawnPt = EgoManeuverEndLane.centerline.start  # Start of end lane — typically aligns with intersection entry / crosswalk
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Pedestrian at IntSpawnPt offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading - 90 deg,  # Facing across lane (i.e., crossing from left)
    with regionContainedIn None,
    with behavior AdvBehavior()
