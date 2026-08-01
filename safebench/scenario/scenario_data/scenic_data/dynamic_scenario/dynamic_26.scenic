'''The ego attempts an unprotected left turn at an intersection while yielding to an oncoming car when the oncoming car's suddenly brakes, necessitating the ego to rapidly reassess the situation and adjust its turn.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is within a significant range to impact the ego's maneuver.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_BRAKE_DISTANCE
    # Once within a critical distance of the ego's trajectory, the adversarial vehicle initiates a sudden braking maneuver.
    while True:
        take SetBrakeAction(globalParameters.OPT_BRAKE)  # Continues to apply brakes to simulate an emergency or unexpected stop.

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection.
param OPT_BRAKE_DISTANCE = Range(0, 4)  # The critical distance at which the adversarial vehicle begins its sudden stop.
param OPT_BRAKE = Range(0, 1)  # The intensity of the braking action, potentially simulating an abrupt or gentle stop.

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
param OPT_GEO_Y_DISTANCE = Range(10, 50)  # Distance ahead along road direction for oncoming agent

# Identify the oncoming lane (assumed to be _laneToLeft in a two-lane undivided road; consistent with prior examples)
laneSec = network.laneSectionAt(ego)
advLaneSec = laneSec._laneToLeft
if advLaneSec is None:
    advLaneSec = laneSec._laneToRight
if advLaneSec is None:
    advLaneSec = Uniform(*network.laneSections)
require advLaneSec is not None
advLane = advLaneSec

# Compute spawn point ahead along ego's road direction, then project onto oncoming lane centerline
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
if advLane is None:
    advLane = Uniform(*network.laneSections)
require advLane is not None
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt] + 180 deg  # Opposite direction: oncoming traffic

# Spawn the adversarial agent in the oncoming lane, facing opposite to ego's direction
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
