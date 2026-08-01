'''The ego vehicle is preparing to change lanes to evade a slow-moving leading vehicle; the adversarial car in the target lane starts weaving between lanes, making it difficult for the ego vehicle to predict its position and safely execute the lane change.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while True:
        do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED) until distance to self < globalParameters.OPT_ADV_DISTANCE
        
        # Perform unpredictable weaving: alternate between current lane and adjacent lanes
        for _ in range(globalParameters.OPT_WEAVE_COUNT):
            if len(network.laneSectionAt(self).adjacentLanes) > 0:
                targetLaneSec = network.laneSectionAt(self).adjacentLanes[0]
                do LaneChangeBehavior(laneSectionToSwitch=targetLaneSec, target_speed=globalParameters.OPT_ADV_SPEED)
            
            # Wait a variable number of steps before next weave
            for _ in range(globalParameters.OPT_WAIT_STEPS):
                wait

param OPT_ADV_SPEED = Range(5, 15)
param OPT_ADV_DISTANCE = Range(0, 20)
param OPT_WEAVE_COUNT = Range(1, 3)
param OPT_WAIT_STEPS = Range(0, 15)
# Identifying lane sections with at least one adjacent lane in the same direction
# (i.e., at least one of _laneToLeft or _laneToRight exists and is forward)
laneSecsWithAdjacentForward = []
for lane in network.lanes:
    for laneSec in lane.sections:
        hasLeftForward = laneSec._laneToLeft is not None and laneSec._laneToLeft.isForward == laneSec.isForward
        hasRightForward = laneSec._laneToRight is not None and laneSec._laneToRight.isForward == laneSec.isForward
        if hasLeftForward or hasRightForward:
            laneSecsWithAdjacentForward.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
if len(laneSecsWithAdjacentForward) == 0:
    laneSecsWithAdjacentForward = network.laneSections
egoLaneSec = Uniform(*laneSecsWithAdjacentForward)
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for adversarial agent's lateral maneuver
param OPT_LATERAL_OFFSET = Range(-2, 2)        # Lateral offset from ego's centerline (positive = right, negative = left)
param OPT_LONGITUDINAL_DISTANCE = Range(-10, 15)  # Distance ahead of (positive) or behind (negative) ego along road direction
param OPT_MANEUVER_SPEED = Range(3, 8)          # Speed during lane-crossing maneuver

# Determine target lane based on intended direction: use _laneToRight or _laneToLeft as appropriate
# Since direction is not fixed in description, we assume right-lane maneuver as default (consistent with first example);
# if left is needed, replace `_laneToRight` with `_laneToLeft` — but per Scenic 2.1 best practice, we keep it parametrically agnostic here.
# However, the description says "right or left, depending on intended lane change", and no explicit direction is given,
# so we follow the *most common pattern in examples*: use _laneToRight unless specified otherwise.
# To support both, we rely on external globalParameters.OPT_TARGET_LANE_SIDE (e.g., 'right' or 'left') — but since that’s not used in prior snippets,
# and per instruction to match existing style, we choose _laneToRight as in first snippet.

laneSec = network.laneSectionAt(ego)
if laneSec is None:
    laneSec = egoLaneSec
require laneSec is not None
advLaneSec = laneSec._laneToRight
if advLaneSec is None:
    advLaneSec = laneSec._laneToLeft
if advLaneSec is None:
    advLaneSec = egoLaneSec
require advLaneSec is not None
advLane = advLaneSec
if advLane is None:
    advLane = egoLaneSec
require advLane is not None

# Spawn point aligned longitudinally with ego, then shifted laterally into target lane
BaseSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_LONGITUDINAL_DISTANCE
# Project onto target lane centerline to ensure valid position in that lane
if advLane is None:
    advLane = egoLaneSec
    if advLane is None:
        advLane = egoLaneSec
    require advLane is not None
projected = advLane.centerline.project(BaseSpawnPt.position)
projectPt = Vector(*projected.coords[0])
if advLane is None:
    advLane = egoLaneSec
require advLane is not None
advHeading = advLane.orientation[projectPt]

# Spawn the adversarial car at that projected point, with optional small lateral jitter to simulate "overlapping planned path"
# Use OPT_LATERAL_OFFSET to shift slightly toward ego's current lane (i.e., across markings)
# In Scenic 2.1, `offset along heading by` applies in local frame; to shift *laterally*, we rotate by 90 deg
lateralShift = globalParameters.OPT_LATERAL_OFFSET @ 0
# But note: prior snippets use `offset along heading by SHIFT` where SHIFT is a vector in heading-aligned coords.
# So to get lateral displacement: use `offset along (heading + 90 deg) by globalParameters.OPT_LATERAL_OFFSET`
AdvSpawnPt = BaseSpawnPt offset along (advHeading + 90 deg) by (globalParameters.OPT_LATERAL_OFFSET @ 0)

# Ensure final position lies on advLane (optional projection again for robustness)
if advLane is None:
    advLane = egoLaneSec
    if advLane is None:
        advLane = egoLaneSec
    require advLane is not None
finalProjected = advLane.centerline.project(AdvSpawnPt)
finalPt = Vector(*finalProjected.coords[0])
if advLane is None:
    advLane = egoLaneSec
require advLane is not None
finalHeading = advLane.orientation[finalPt]

# Spawn the Adversarial Agent
AdvAgent = Car at finalPt,
    with heading finalHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
