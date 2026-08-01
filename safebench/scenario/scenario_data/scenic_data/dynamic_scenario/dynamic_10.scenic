'''The ego vehicle is attempting to change lanes to avoid a slow-moving leading vehicle; the adversarial car in the target lane suddenly merges into the ego vehicle's original lane, blocking the ego vehicle from returning to its initial position.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED) until (
        distance to self < globalParameters.OPT_ADV_DISTANCE and
        network.laneAt(self) is not network.laneAt(ego) )
    # Identify ego's original lane section (i.e., the lane ego is currently in — which the adversarial car will merge into to block return)
    targetLaneSec = network.laneSectionAt(ego)
    if targetLaneSec is None:
        targetLaneSec = egoLaneSec
    require targetLaneSec is not None
    # Execute the lane change into ego's current lane to block its return maneuver
    do LaneChangeBehavior(laneSectionToSwitch=targetLaneSec, target_speed=globalParameters.OPT_ADV_SPEED)

param OPT_ADV_SPEED = Range(5, 10)
param OPT_ADV_DISTANCE = Range(0, 20)
# Identifying lane sections with at least one adjacent parallel lane in the same direction
# (i.e., either a left lane or right lane moving in the same forward direction)
laneSecsWithParallelLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        hasParallelLeft = (laneSec._laneToLeft is not None and 
                           laneSec._laneToLeft.isForward == laneSec.isForward)
        hasParallelRight = (laneSec._laneToRight is not None and 
                            laneSec._laneToRight.isForward == laneSec.isForward)
        if hasParallelLeft or hasParallelRight:
            laneSecsWithParallelLane.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
if len(laneSecsWithParallelLane) == 0:
    laneSecsWithParallelLane = network.laneSections
egoLaneSec = Uniform(*laneSecsWithParallelLane)
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_Y_DISTANCE = Range(0, 30)  # Distance ahead along ego's lane for adversarial spawn in target lane
param OPT_LATERAL_OFFSET = Range(1.5, 4.0)  # Lateral distance from ego's lane center to target lane center (e.g., right or left)
param OPT_MERGE_DISTANCE = Range(-5, 5)  # Longitudinal offset during merge (to position directly ahead or adjacent)

# Identify the target lane (e.g., _laneToRight for right merge; _laneToLeft for left merge — assumed configurable via context)
# Since direction is not specified as left/right in description, we use generic lateral offset approach
advLaneSec = network.laneSectionAt(ego)._laneToRight  # Default to right lane; adjust per scenario variant if needed
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = egoLaneSec
require advLaneSec is not None
advLane = advLaneSec
if advLane is None:
    advLane = egoLaneSec
require advLane is not None

# Spawn point in target lane, ahead of ego
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

# Adversarial agent starts in target lane, then merges laterally into ego's lane
# We model its *initial* spawn in the target lane (as described: "initially in the target lane")
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()
