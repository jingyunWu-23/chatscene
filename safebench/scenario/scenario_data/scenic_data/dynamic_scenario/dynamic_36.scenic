'''The ego vehicle is approaching the intersection; the adversarial car (on the right) suddenly accelerates and enters the intersection first and suddenly stop.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to be a threat.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance to self) < globalParameters.OPT_ADV_DISTANCE or (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    # Accelerates into the intersection.
    while (distance from self to egoTrajectory) > globalParameters.OPT_STOP_DISTANCE:
        take SetThrottleAction(globalParameters.OPT_THROTTLE)  # Increase throttle to accelerate into intersection.
    while True:
        take SetSpeedAction(0)  # Abruptly stops.

param OPT_ADV_SPEED = Range(5, 15)  # Speed at which the adversarial vehicle approaches before acceleration.
param OPT_ADV_DISTANCE = Range(0, 20)  # Distance threshold to start aggressive maneuver.
param OPT_THROTTLE = Range(0.5, 1)  # Throttle level for unexpected acceleration.
param OPT_STOP_DISTANCE = Range(0, 2)  # Critical distance from ego's trajectory at which to stop abruptly.
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Setup the adversarial agent's spawn point on the right-side approach lane adjacent to the intersection
param OPT_GEO_X_DISTANCE = Range(2, 8)
param OPT_GEO_Y_DISTANCE = Range(-10, 10)
param OPT_ADV_SPEED = Range(0, 3)

# Get the right-adjacent lane of the ego's current lane section (approach lane to intersection)
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)
require advLaneSec is not None
advLane = advLaneSec.lane
# Use a point near the start of the lane (approach side) to position near intersection
IntSpawnPt = advLane.centerline.start
# Offset laterally outward (perpendicular to lane heading) to place agent adjacent but not on centerline
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.offset along IntSpawnPt.heading by SHIFT).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior(target_speed=globalParameters.OPT_ADV_SPEED)