'''The ego attempts an unprotected left turn at an intersection while yielding to an oncoming car when the oncoming car veer erratically.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to influence the ego's maneuver.
    # Initiates erratic steering maneuvers immediately upon entering the critical zone.
    for steer in globalParameters.STEER_LIST:
        take SetSpeedAction(self.speed), SetSteerAction(steer)  # Applies a series of random steering adjustments.

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection.
param STEER_LIST = [Range(-globalParameters.OPT_STEER, globalParameters.OPT_STEER) for i in range(1000)]  # List of random steering angles.
param OPT_STEER = Range(0.1, 0.8)  # Magnitude range for erratic steering perturbations.

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
param OPT_GEO_Y_DISTANCE = Range(10, 50)  # Distance ahead of ego across the intersection

# Determine the oncoming lane directly ahead across the intersection
# Since the agent is in the *near oncoming lane*, and traveling *toward* the ego’s path,
# we assume it's in the lane that opposes ego's direction — typically the lane to the left
# (i.e., ego's `_laneToLeft`), but positioned *across the intersection*, meaning aligned
# with ego's forward direction beyond the intersection point.
laneSec = network.laneSectionAt(ego)
oncomingLaneSec = laneSec._laneToLeft
if oncomingLaneSec is None:
    oncomingLaneSec = laneSec._laneToRight
if oncomingLaneSec is None:
    oncomingLaneSec = laneSec
require oncomingLaneSec is not None
oncomingLane = oncomingLaneSec

# Compute a spawn point ahead along ego's forward direction, then project onto oncoming lane
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*oncomingLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = oncomingLane.orientation[projectPt] + 180 deg  # Facing toward ego (i.e., opposite of oncoming lane's default orientation)

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
