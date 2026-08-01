'''The ego vehicle is turning left at an intersection; the adversarial pedestrian on the opposite sidewalk suddenly crosses the road from the right front and stops in the middle of the intersection.'''
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
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.LEFT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
if egoInitLane is None:
    egoInitLane = Uniform(*network.laneSections)
require egoInitLane is not None
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
param OPT_GEO_X_DISTANCE = Range(2, 8)   # distance forward along ego's heading (into intersection)
param OPT_GEO_Y_DISTANCE = Range(-3, 3)  # lateral offset to align with crosswalk entry point

-- Get the ego's start lane and its orientation at the end (approaching intersection)
EgoManeuverStartLane = egoManeuver.startLane
if EgoManeuverStartLane is None:
    EgoManeuverStartLane = Uniform(*network.laneSections)
require EgoManeuverStartLane is not None
IntSpawnPt = EgoManeuverStartLane.centerline.end

-- Offset into the intersection: forward along ego's heading (to reach crosswalk entry),
-- then laterally to position on the right side of the ego's path (i.e., right front relative to ego)
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE

-- Adversarial agent enters from opposite sidewalk → heading should be perpendicular to ego's,
-- crossing *into* the intersection — i.e., aligned with crosswalk direction.
-- Since it spawns from right front and crosses mid-turn, its heading should be ~90 deg left of ego's
-- (to walk across the road the ego is turning into), but we assume crosswalk is orthogonal to ego's lane.
-- Use ego's heading + 90 deg for crossing *from right*, i.e., moving leftward across ego's path.
AdvAgent = Pedestrian at IntSpawnPt offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 90 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()
