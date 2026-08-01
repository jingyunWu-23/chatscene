'''The ego vehicle is turning right; the adversarial car (positioned ahead on the right) reverses abruptly.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    # Wait until the adversarial vehicle decides to reverse (no external trigger condition specified, so immediate reversal)
    take SetReverseAction(True)  # Initiates reversal.
    take SetThrottleAction(globalParameters.OPT_THROTTLE)  # Applies throttle to drive backward.

param OPT_THROTTLE = Range(0.5, 1.0)  # Intensity of throttle during reversal.
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Setup the leading vehicle's spawn point directly in front of the ego to simulate a slow-moving vehicle
param OPT_LEADING_DISTANCE = Range(0, 30)
param OPT_LEADING_SPEED = Range(1, 5)
LeadingSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_LEADING_DISTANCE
LeadingAgent = Car at LeadingSpawnPt,
    with behavior FollowLaneBehavior(target_speed=globalParameters.OPT_LEADING_SPEED)

# Identifying the adjacent right lane (e.g., side street/driveway/curb lane) for the Adversarial Agent
# and setting its spawn point ahead on that lane
param OPT_GEO_Y_DISTANCE = Range(0, 30)
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)
require advLaneSec is not None
advLane = advLaneSec
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
