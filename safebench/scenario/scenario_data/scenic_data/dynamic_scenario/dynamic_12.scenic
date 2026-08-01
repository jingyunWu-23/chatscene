'''The ego vehicle is attempting to change lanes to avoid a slow-moving leading vehicle; the adversarial car in the target lane suddenly slows down, matching the speed of the leading vehicle, and effectively blocking the ego vehicle from completing the lane change.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"
param OPT_LEADING_SPEED = Range(1, 8)

param OPT_ADV_SPEED = Range(5, 10)
param OPT_ADV_DISTANCE = Range(0, 20)

behavior AdvBehavior():
    do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED) until (distance to self) < globalParameters.OPT_ADV_DISTANCE
    while True:
        take SetVelocityAction(*LeadingAgent.velocity)
# Identifying lane sections with at least one adjacent parallel lane in the same direction
# (i.e., either a left lane *or* a right lane moving forward if current section is forward,
# or backward if current section is backward — i.e., same isForward value)
laneSecsWithAdjacentParallelLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        hasAdjacentParallel = False
        if laneSec._laneToLeft is not None and laneSec._laneToLeft.isForward == laneSec.isForward:
            hasAdjacentParallel = True
        if laneSec._laneToRight is not None and laneSec._laneToRight.isForward == laneSec.isForward:
            hasAdjacentParallel = True
        if hasAdjacentParallel:
            laneSecsWithAdjacentParallelLane.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
if len(laneSecsWithAdjacentParallelLane) == 0:
    laneSecsWithAdjacentParallelLane = network.laneSections
egoLaneSec = Uniform(*laneSecsWithAdjacentParallelLane)
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_LEADING_DISTANCE = Range(0, 30)
param OPT_ADV_SPEED_HIGH = Range(8, 12)
param OPT_ADV_SPEED_LOW = Range(1, 4)
param OPT_GEO_Y_DISTANCE = Range(0, 30)

# Setup the leading vehicle's spawn point directly in front of the ego to simulate a slow-moving vehicle (provokes merge attempt)
LeadingSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_LEADING_DISTANCE
LeadingAgent = Car at LeadingSpawnPt,
    with behavior FollowLaneBehavior(target_speed=globalParameters.OPT_LEADING_SPEED)

# Identifying the adjacent lane (target lane) for the Adversarial Agent — right or left depending on merge intent
# Since description says "target (right or left) lane", and no direction is specified, we follow pattern from prior examples:
# Use _laneToRight by default unless context implies left; but here it's ambiguous.
# However, Scenic 2.1 requires deterministic lane selection per snippet — so we must pick one.
# Given symmetry and prior examples using both, and no directional cue in description, we choose _laneToRight
# (consistent with first example, and most common merge scenario unless stated otherwise).
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = egoLaneSec
require advLaneSec is not None
advLane = advLaneSec
if advLane is None:
    advLane = egoLaneSec
require advLane is not None

# Spawn point for adversarial agent in target lane, ahead of ego (but not necessarily aligned with LeadingSpawnPt)
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
if advLane is None:
    advLane = egoLaneSec
    if advLane is None:
        advLane = egoLaneSec
    require advLane is not None
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
if advLane is None:
    advLane = egoLaneSec
require advLane is not None
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent directly ahead in the target lane, initially fast then decelerating
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
