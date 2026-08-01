'''The ego vehicle is entering the intersection; the adversarial vehicle comes from the right and turns left and stop, causing a near collision with the ego vehicle.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is within a threatening proximity.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_STEER_DISTANCE
    # Once close to the ego's trajectory, the adversarial vehicle initiates a left turn.
    while True:
        take SetSpeedAction(self.speed)  # Continues moving at its current speed
        take SetSteerAction(-globalParameters.OPT_STEER)  # Makes an abrupt left steering adjustment (negative for left)
    # After turning into ego's path, abruptly stop.
    do FollowTrajectoryBehavior(0, advTrajectory) until (self.speed < 0.1)  # Enforce stopping by setting target speed to 0

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches.
param OPT_STEER_DISTANCE = Range(0, 4)  # Distance from ego's trajectory at which the vehicle starts to turn.
param OPT_STEER = Range(0.5, 1.0)  # Defines the intensity of the steering action (magnitude; sign handled in behavior).

intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoInitLane = Uniform(*intersection.incomingLanes)
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.STRAIGHT, egoInitLane.maneuvers))
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
EgoManeuverStartLane = egoManeuver.startLane
if EgoManeuverStartLane is None:
    EgoManeuverStartLane = Uniform(*network.laneSections)
require EgoManeuverStartLane is not None
egoSpawnPt = OrientedPoint in EgoManeuverStartLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Defining adversarial maneuvers as those conflicting with the ego's straight path
advManeuvers = filter(lambda i: i.type == ManeuverType.LEFT_TURN, egoManeuver.conflictingManeuvers)
if len(advManeuvers) == 0:
    advManeuvers = network.laneSections
advManeuver = Uniform(*advManeuvers)
advTrajectory = [advManeuver.startLane, advManeuver.connectingLane, advManeuver.endLane]
AdvManeuverConnectingLane = advManeuver.connectingLane
if AdvManeuverConnectingLane is None:
    AdvManeuverConnectingLane = Uniform(*network.laneSections)
require AdvManeuverConnectingLane is not None
advSpawnPt = AdvManeuverConnectingLane.centerline[0]  # Initial point on the connecting lane's centerline
AdvManeuverConnectingLane = advManeuver.connectingLane
if AdvManeuverConnectingLane is None:
    AdvManeuverConnectingLane = Uniform(*network.laneSections)
require AdvManeuverConnectingLane is not None
IntSpawnPt = AdvManeuverConnectingLane.centerline.start  # Start of the connecting lane centerline

param OPT_GEO_Y_DISTANCE = Range(-10, 10)
# Setting up the adversarial agent
AdvAgent = Car following roadDirection from IntSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE,
    with heading IntSpawnPt.heading,
    with regionContainedIn None,
    with behavior AdvBehavior()

# Requirements to ensure the adversarial agent's relative position and trajectory are correctly aligned with the scenario's needs
require 70 deg <= RelativeHeading(AdvAgent) <= 110 deg  # Ensuring the agent approaches from an angle indicative of crossing
require any([AdvAgent.position in traj for traj in [advManeuver.startLane, advManeuver.connectingLane, advManeuver.endLane]])
