'''The ego vehicle is making an unprotected left turn; the adversarial vehicle approaches the intersection at a normal speed but then suddenly attempts to make a last-second right turn.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to affect the ego's maneuver.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_STEER_DISTANCE
    # Initiates a sudden right turn as it gets close to the intersection.
    while True:
        take SetSpeedAction(self.speed)  # Maintains its current speed
        take SetSteerAction(globalParameters.OPT_STEER)  # Executes a sharp turn

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection.
param OPT_STEER_DISTANCE = Range(0, 4)  # The distance at which the adversarial vehicle starts its sudden maneuver.
param OPT_STEER = Range(0.5, 1.0)  # The intensity of the steering action, specifying the sharpness of the turn.

## MONITORS
monitor TrafficLights:
    freezeTrafficLights()
    while True:
        if withinDistanceToTrafficLight(ego, 100):
            setClosestTrafficLightStatus(ego, "green")
        if withinDistanceToTrafficLight(AdvAgent, 100):
            setClosestTrafficLightStatus(AdvAgent, "green")
        wait

intersection = Uniform(*filter(lambda i: i.is4Way and i.isSignalized, network.intersections))
egoInitLane = Uniform(*intersection.incomingLanes)
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.LEFT_TURN, egoInitLane.maneuvers))
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
EgoManeuverStartLane = egoManeuver.startLane
if EgoManeuverStartLane is None:
    EgoManeuverStartLane = Uniform(*network.laneSections)
require EgoManeuverStartLane is not None
egoSpawnPt = OrientedPoint in EgoManeuverStartLane.centerline

# Setting up the ego vehicle at the initial position
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Parameters for scenario elements
param OPT_GEO_Y_DISTANCE = Range(10, 50)  # Distance ahead along ego's road direction to place adversarial agent in opposite lane

# Identify the oncoming lane — the lane directly facing ego (i.e., opposite-direction lane in same road)
laneSec = network.laneSectionAt(ego)
# Assuming `_laneToLeft` or `_laneToRight` corresponds to the opposing-lane direction depending on traffic rule;
# In right-hand traffic, the oncoming lane is typically `_laneToLeft` of ego's lane section.
# Since the description says "lane directly facing the ego", we use the opposing-direction lane in the same road segment.
oppLane = laneSec._laneToLeft  # consistent with first example's use for oncoming traffic

# Compute spawn point along ego's forward direction, then project onto opposite lane's centerline
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
if oppLane is None:
    oppLane = Uniform(*network.laneSections)
require oppLane is not None
projectPt = Vector(*oppLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = oppLane.orientation[projectPt]  # heading aligned with lane direction (i.e., toward ego)

# Spawn the adversarial agent head-on (so its heading should be *toward* ego — i.e., opposite of oppLane's natural orientation if oppLane is defined as forward in its own direction)
# Since oppLane.orientation[projectPt] gives the *forward* direction of that lane, and we want the agent to approach ego head-on,
# we rotate by 180° so it travels *against* that lane’s natural direction — i.e., toward ego.
AdvAgent = Car at projectPt,
    with heading advHeading + 180 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()
