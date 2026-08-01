'''The ego is driving straight through an intersection when a crossing vehicle runs the red light and unexpectedly accelerates, forcing the ego to quickly reassess the situation and perform a collision avoidance maneuver.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to be a threat.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance to self) < globalParameters.OPT_ADV_DISTANCE or (distance from self to egoTrajectory) < globalParameters.OPT_ACCEL_DISTANCE
    # Runs the red light and accelerates into the intersection.
    while (distance from self to egoTrajectory) > globalParameters.OPT_ACCEL_DISTANCE:
        take SetThrottleAction(globalParameters.OPT_THROTTLE)  # Applies throttle to accelerate unexpectedly.
    # Continue accelerating or maintain high speed through intersection — no explicit stop unless implied by context; behavior ends after acceleration phase.
    while True:
        take SetThrottleAction(globalParameters.OPT_THROTTLE)

param OPT_ADV_SPEED = Range(5, 15)  # Speed at which the adversarial vehicle initially approaches the intersection.
param OPT_ADV_DISTANCE = Range(0, 20)  # Distance threshold to begin aggressive acceleration.
param OPT_THROTTLE = Range(0.7, 1.0)  # High throttle intensity to reflect unexpected, aggressive acceleration.
param OPT_ACCEL_DISTANCE = Range(0, 3)  # Critical distance from ego's trajectory at which acceleration is triggered (e.g., just before entering intersection).

## MONITORS
monitor TrafficLights:
    freezeTrafficLights()
    while True:
        if withinDistanceToTrafficLight(ego, 100):
            setClosestTrafficLightStatus(ego, "green")
        if withinDistanceToTrafficLight(AdvAgent, 100):
            setClosestTrafficLightStatus(AdvAgent, "red")
        wait

intersection = Uniform(*filter(lambda i: i.is4Way and i.isSignalized, network.intersections))
egoInitLane = Uniform(*intersection.incomingLanes)
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.STRAIGHT, egoInitLane.maneuvers))
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
param OPT_GEO_BLOCKER_Y_DISTANCE = Range(0, 40)
param OPT_GEO_X_DISTANCE = Range(-4, 4)  # Lateral offset: negative = left, positive = right relative to ego's heading
param OPT_GEO_Y_DISTANCE = Range(2, 8)    # Forward distance from blocker (or ego spawn) along road direction

# Setup for the blocking car that the ego must bypass
laneSec = network.laneSectionAt(ego)
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_BLOCKER_Y_DISTANCE
Blocker = Car at IntSpawnPt,
    with heading IntSpawnPt.heading,
    with regionContainedIn None

# Setup for the adversarial car entering intersection perpendicularly (crossing ego's path)
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Car at Blocker offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 90 deg,  # Right-crossing (default); variation handled by OPT_GEO_X_DISTANCE sign
    with regionContainedIn None,
    with behavior AdvBehavior()
