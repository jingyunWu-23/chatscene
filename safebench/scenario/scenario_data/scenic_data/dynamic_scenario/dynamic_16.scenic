'''The ego encounters a parked car blocking its lane and must use the opposite lane to bypass the vehicle, carefully assessing the situation and yielding to oncoming traffic, when an oncoming motorcyclist swerves into the lane unexpectedly, necessitating the ego to brake or maneuver to avoid a potential accident.'''
Town = 'Town01'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    laneChangeCompleted = False
    try:
        do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED)
    interrupt when (distance from self to ego) < globalParameters.OPT_LANE_CHANGE_TRIGGER_DISTANCE and network.laneAt(self) is not network.laneAt(ego) and not laneChangeCompleted:
        LaneSec = network.laneSectionAt(ego)
        do LaneChangeBehavior(
            laneSectionToSwitch=LaneSec,
            target_speed=globalParameters.OPT_ADV_SPEED)
        laneChangeCompleted = True

param OPT_ADV_SPEED = Range(1, 15)  # Speed range for the adversarial motorcyclist during swerve maneuver
param OPT_LANE_CHANGE_TRIGGER_DISTANCE = Range(5, 25)  # Distance threshold to trigger unexpected lane change into ego's bypass lane
# Collecting lane sections that have a left lane (opposite traffic direction) and no right lane (single forward road)
laneSecsWithLeftLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec._laneToLeft is not None and laneSec._laneToRight is None:
            if laneSec._laneToLeft.isForward != laneSec.isForward:
                laneSecsWithLeftLane.append(laneSec)

# Selecting a random lane section that matches the criteria
egoLaneSec = Uniform(*laneSecsWithLeftLane)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_BLOCKER_Y_DISTANCE = Range(0, 40)
param OPT_GEO_X_DISTANCE = Range(-8, 0)  # Lateral offset toward ego's lane (bypass lane)
param OPT_GEO_Y_DISTANCE = Range(10, 30)

# Setting up the parked car that blocks the ego's original lane and limits visibility
laneSec = network.laneSectionAt(ego)  # Assuming network.laneSectionAt(ego) is predefined in the geometry part
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_BLOCKER_Y_DISTANCE
Blocker = Car at IntSpawnPt,
    with heading IntSpawnPt.heading,
    with regionContainedIn None

# Setup for the motorcyclist starting in the oncoming lane (opposite direction), then swerving into ego's bypass lane
# First, locate the oncoming lane (typically _laneToLeft for right-hand traffic, assuming ego is in rightmost drivable lane)
oncomingLaneSec = laneSec._laneToLeft
require oncomingLaneSec is not None
oncomingLane = oncomingLaneSec.lane
# Spawn point in oncoming lane, ahead of blocker (so motorcyclist approaches blocker then swerves)
oncomingSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectedOncomingPos = Vector(*oncomingLane.centerline.project(oncomingSpawnPt.position).coords[0])
oncomingHeading = oncomingLane.orientation[projectedOncomingPos]

# Adversarial agent starts in oncoming lane, facing opposite direction (i.e., 180° relative to ego's roadDirection)
# Then laterally swerves — we model its *initial spawn* in the oncoming lane, but its behavior (AdvBehavior) handles the swerve
AdvAgent = Motorcycle at projectedOncomingPos,
    with heading oncomingHeading + 180 deg,  # Facing oncoming direction
    with regionContainedIn None,
    with behavior AdvBehavior()