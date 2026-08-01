'''The ego starts an unprotected left turn at an intersection while yielding to an oncoming car when the oncoming car's throttle malfunctions, leading to an unexpected acceleration and forcing the ego to quickly modify its turning path to avoid a collision.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial car waits until it is within 60 meters of the ego vehicle.
    do FollowLaneBehavior(globalParameters.OPT_ADV_SPEED) until (distance to self) < globalParameters.OPT_ADV_DISTANCE
    while True:
        take SetThrottleAction(globalParameters.OPT_MALFUNCTION_THROTTLE)  # Throttle malfunction causes sustained, unexpected acceleration.

param OPT_ADV_SPEED = Range(0, 15)  # Initial speed before malfunction; e.g., approaching intersection at moderate speed.
param OPT_ADV_DISTANCE = Range(0, 20)  # Distance threshold at which malfunction triggers (e.g., during ego’s left turn).
param OPT_MALFUNCTION_THROTTLE = Range(0.7, 1)  # High, unmodulated throttle reflecting loss of control — no braking or modulation.

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
egoSpawnPt = OrientedPoint in egoManeuver.startLane.centerline

# Setting up the ego vehicle at the initial position
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Parameters for scenario elements
param OPT_GEO_X_DISTANCE = Range(-5, 5)      # Lateral offset from exact opposite (to allow small variation)
param OPT_GEO_Y_DISTANCE = Range(10, 40)     # Distance ahead along the oncoming road direction

# Identify the oncoming lane: assume ego is on a two-way road; _laneToLeft is the opposing-direction lane
laneSec = network.laneSectionAt(ego)
oncomingLaneSec = laneSec._laneToLeft
if oncomingLaneSec is None:
    oncomingLaneSec = laneSec._laneToRight
if oncomingLaneSec is None:
    oncomingLaneSec = laneSec
require oncomingLaneSec is not None
oncomingLane = oncomingLaneSec

# Compute spawn point in the oncoming lane, directly opposite and ahead along its centerline
# First, get a point directly opposite ego across the intersection — we use egoSpawnPt projected onto oncomingLane's centerline
# Since Scenic 2.1 does not support direct "opposite across intersection", we approximate by moving along ego's roadDirection
# then projecting onto oncomingLane — but per examples, we follow roadDirection *from ego* and project onto target lane
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*oncomingLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = oncomingLane.orientation[projectPt]

# Spawn the adversarial agent in the oncoming lane, facing toward ego (i.e., opposite to oncomingLane's forward direction)
# Note: In CARLA, lane orientation points in the lane's *forward* direction; since this is an oncoming lane,
# the agent must head *against* that direction to approach ego — so heading = advHeading + 180 deg
AdvAgent = Car at projectPt,
    with heading advHeading + 180 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()
