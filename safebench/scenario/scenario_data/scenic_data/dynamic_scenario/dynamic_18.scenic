'''The ego approaches a parked car obstructing its lane and must use the opposite lane to go around when an oncoming car suddenly turns into the ego's path without signaling, requiring the ego to react quickly and take evasive action to prevent a collision.'''
Town = 'Town01'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is within a threatening proximity.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_STEER_DISTANCE
    # Once close to the ego's trajectory, the adversarial vehicle suddenly turns into the ego's path without signaling.
    while True:
        take SetSpeedAction(self.speed)  # Continues moving at its current speed
        take SetSteerAction(globalParameters.OPT_STEER)  # Makes an abrupt steering adjustment

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection.
param OPT_STEER_DISTANCE = Range(0, 4)  # Distance from ego's trajectory at which the vehicle starts to turn.
param OPT_STEER = Range(-1.0, 1.0)  # Defines the intensity and direction of the steering action; negative for left, positive for right.
# Collecting lane sections that have a left lane (opposite traffic direction) and no right lane (single forward road)
laneSecsWithLeftLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec._laneToLeft is not None and laneSec._laneToRight is None:
            if laneSec._laneToLeft.isForward != laneSec.isForward:
                laneSecsWithLeftLane.append(laneSec)

# Selecting a random lane section that matches the criteria
if len(laneSecsWithLeftLane) == 0:
    laneSecsWithLeftLane = network.laneSections
egoLaneSec = Uniform(*laneSecsWithLeftLane)
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

# Parked car obstructing ego's lane
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
parkedCar = Car on egoLaneSec.centerline,
    with position egoSpawnPt.position,
    with heading egoSpawnPt.heading,
    with blueprint PARKED_CAR_MODEL
# Parameters for scenario elements
param OPT_GEO_BLOCKER_Y_DISTANCE = Range(0, 40)
param OPT_GEO_X_DISTANCE = Range(-8, 0)  # Offset for the agent in the opposite lane
param OPT_GEO_Y_DISTANCE = Range(10, 30)

# Setting up the parked car that blocks the ego's path
laneSec = network.laneSectionAt(ego)  # Assuming network.laneSectionAt(ego) is predefined in the geometry part
if laneSec is None:
    laneSec = egoLaneSec
require laneSec is not None
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_BLOCKER_Y_DISTANCE
Blocker = Car at IntSpawnPt,
    with heading IntSpawnPt.heading,
    with regionContainedIn None

# Setup for the motorcyclist who unexpectedly enters the scene
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Car at Blocker offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 180 deg,  # The agent is facing the opposite direction, indicating oncoming
    with regionContainedIn laneSec._laneToLeft,  # Positioned in the left lane, assuming it's the oncoming traffic lane
    with behavior AdvBehavior()
