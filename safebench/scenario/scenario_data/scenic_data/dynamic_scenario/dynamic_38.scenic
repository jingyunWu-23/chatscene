'''The ego vehicle is entering the intersection; the adversarial vehicle comes from the opposite direction and turns left and stop, causing a near collision with the ego vehicle.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # Wait until the adversarial vehicle is within threatening proximity.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_STEER_DISTANCE
    # Initiates left turn across the intersection.
    take SetSteerAction(globalParameters.OPT_STEER)
    # Abruptly stops in the ego vehicle's path after turning.
    while True:
        take SetSpeedAction(0)  # Full stop

param OPT_ADV_SPEED = Range(5, 15)  # Speed at which the adversarial vehicle approaches from the opposite direction.
param OPT_STEER_DISTANCE = Range(0, 4)  # Distance from ego's trajectory at which the left turn begins.
param OPT_STEER = Range(-1.0, -0.5)  # Sharp left steering angle to cross the intersection.
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.STRAIGHT or m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
if egoInitLane is None:
    egoInitLane = Uniform(*network.laneSections)
require egoInitLane is not None
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

# Identify the opposite lane (facing ego) just before the intersection centerline
# First, get the ego's current lane section and find the opposing lane (typically across the centerline)
egoLaneSection = network.laneSectionAt(ego)
# In CARLA/Scenic 2.1, `_oppositeLane` is the standard attribute for the directly opposing lane (same road, opposite direction)
# If not available, fallback to using the lane with opposite heading — but per Scenic 2.1 CARLA schema, `_oppositeLane` exists
advLaneSec = egoLaneSection._oppositeLane
require advLaneSec is not None
advLane = advLaneSec

# Get a point near the intersection centerline: project a point just before the lane's end (approaching intersection)
# Use the start of the opposite lane's centerline segment that aligns with ego's approach
if advLane is None:
    advLane = Uniform(*network.laneSections)
require advLane is not None
# Prefer using `advLane.centerline.end` (i.e., the end closest to ego’s path), then offset backward slightly
if advLane is None:
    advLane = Uniform(*network.laneSections)
require advLane is not None
IntSpawnPt = advLane.centerline.end
# Offset backward along the opposite lane's heading (i.e., toward the intersection centerline, but *just before* it)
param OPT_OPPOSITE_OFFSET = Range(-5, -1)  # meters back from end, placing agent just before centerline
projectPt = IntSpawnPt offset along IntSpawnPt.heading by globalParameters.OPT_OPPOSITE_OFFSET

# Heading must face ego — i.e., opposite to advLane's natural heading (since advLane is opposite-direction lane,
# its heading points *away* from ego; so we flip it to face ego)
advHeading = IntSpawnPt.heading + 180 deg

# Spawn the Adversarial Agent performing left turn across ego's path
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
