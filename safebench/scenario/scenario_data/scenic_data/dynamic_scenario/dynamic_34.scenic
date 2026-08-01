'''The ego vehicle is turning right; the adversarial car (positioned behind on the right) suddenly accelerates and then decelerates.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # Wait until within 60 meters of the ego vehicle.

    do FollowLaneBehavior(globalParameters.OPT_ADV_SPEED) until (distance to self) < globalParameters.OPT_ADV_DISTANCE

    # Sudden acceleration
    take SetThrottleAction(globalParameters.OPT_THROTTLE)
    for _ in range(globalParameters.OPT_DURATION_ACCEL):
        wait

    # Then sudden deceleration
    take SetBrakeAction(globalParameters.OPT_BRAKE)
    for _ in range(globalParameters.OPT_DURATION_BRAKE):
        wait

param OPT_ADV_SPEED = Range(5, 15)
param OPT_ADV_DISTANCE = Range(0, 20)
param OPT_THROTTLE = Range(0.5, 1.0)
param OPT_BRAKE = Range(0, 1)
param OPT_DURATION_ACCEL = Range(5, 15)
param OPT_DURATION_BRAKE = Range(5, 15)
intersection = Uniform(*filter(lambda i: i.is4Way or i.is3Way, network.intersections))
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
# Parameters for scenario elements
param OPT_GEO_Y_DISTANCE = Range(0, 30)  # Distance along road direction (negative for behind)
param OPT_GEO_X_DISTANCE = Range(1, 5)   # Lateral offset to the right

# Identifying the adjacent right lane for the Adversarial Agent
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = Uniform(*network.laneSections)
require advLaneSec is not None
advLane = advLaneSec
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for -globalParameters.OPT_GEO_Y_DISTANCE
if advLane is None:
    advLane = Uniform(*network.laneSections)
require advLane is not None
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent behind and to the right
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
