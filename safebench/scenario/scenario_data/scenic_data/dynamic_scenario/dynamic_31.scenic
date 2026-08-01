'''The ego vehicle is turning right; the adversarial car (positioned ahead on the right) blocks the lane by braking suddenly.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

param OPT_ADV_SPEED = Range(0, 20)
param OPT_ADV_DISTANCE = Range(0, 20)
param OPT_BRAKE = Range(0.7, 1)  # Strong brake to effectively block the ego vehicle's path

behavior AdvBehavior():
    do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED) until (distance to self) < globalParameters.OPT_ADV_DISTANCE
    while True:
        take SetBrakeAction(globalParameters.OPT_BRAKE)
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Setup the leading vehicle's spawn point directly in front of the ego to simulate a slow-moving vehicle (if needed for context — but not required per description)
# Note: Description does not mention a blocker/leading vehicle, so none is added unless implied; here, no blocker is specified.

# Identifying the target lane for the right turn (i.e., the lane to the right of ego's current lane, aligned with turn direction)
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)
require advLaneSec is not None
advLane = advLaneSec.lane

# Compute a spawn point ahead and to the right relative to ego's pre-turn orientation,
# i.e., offset from egoSpawnPt along ego's heading (forward) and rightward (lateral)
param OPT_GEO_X_DISTANCE = Range(5, 20)   # forward distance along ego's heading
param OPT_GEO_Y_DISTANCE = Range(1, 5)     # rightward lateral offset (positive to right)

IntSpawnPt = egoSpawnPt offset along egoSpawnPt.heading by globalParameters.OPT_GEO_X_DISTANCE
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()