'''The ego vehicle is maintaining a constant speed; the adversarial car, comes from the right, blocks multiple lanes by driving extremely slowly, forcing the ego vehicle to change lanes.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

param OPT_SLOW_SPEED = Range(0, 2)
param OPT_BLOCK_DISTANCE = Range(0, 30)
param OPT_BLOCK_LANE_OFFSET = Range(0.5, 2.0)

behavior AdvBehavior():
    while (distance to self) > globalParameters.OPT_BLOCK_DISTANCE:
        wait  # Wait until within blocking range.

    # Drive extremely slowly while offset laterally to block multiple lanes.
    while True:
        take SetSpeedAction(globalParameters.OPT_SLOW_SPEED)
        take SetLaneOffsetAction(globalParameters.OPT_BLOCK_LANE_OFFSET)
# Identifying lane sections with at least one adjacent lane (left or right) moving in the same forward direction
laneSecsWithSameDirAdjacentLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        hasSameDirLeft = laneSec._laneToLeft is not None and laneSec._laneToLeft.isForward == laneSec.isForward
        hasSameDirRight = laneSec._laneToRight is not None and laneSec._laneToRight.isForward == laneSec.isForward
        if hasSameDirLeft or hasSameDirRight:
            laneSecsWithSameDirAdjacentLane.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
egoLaneSec = Uniform(*laneSecsWithSameDirAdjacentLane)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_Y_DISTANCE = Range(0, 30)  # Distance ahead along ego's lane for initial lateral offset point
param OPT_GEO_X_DISTANCE = Range(5, 15)   # Lateral offset into the right adjacent lane(s)

# Identify the rightmost adjacent lane(s) — traverse _laneToRight chain until no more right lane exists
laneSec = network.laneSectionAt(ego)
rightLaneSec = laneSec._laneToRight
if rightLaneSec is None:
    rightLaneSec = laneSec._laneToLeft
if rightLaneSec is None:
    rightLaneSec = laneSec
require rightLaneSec is not None
rightLane = rightLaneSec.lane
# If multiple right lanes exist and we want the *rightmost*, follow chain:
while rightLane and rightLane._laneToRight:
    rightLaneSec = rightLane._laneToRight
    if rightLaneSec is None:
        rightLaneSec = rightLane._laneToLeft
    if rightLaneSec is None:
        rightLaneSec = rightLane
    require rightLaneSec is not None
    rightLane = rightLaneSec.lane

# Define a reference point ahead of ego in ego's lane to project from
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE

# Offset laterally to the rightmost adjacent lane — use perpendicular (rightward) direction
# Since Scenic 2.1 supports `offset along heading by` and `offset perpendicular to`, we use:
# `offset perpendicular to IntSpawnPt.heading by positive value` → rightward in forward-driving context
projectPt = IntSpawnPt offset perpendicular to IntSpawnPt.heading by globalParameters.OPT_GEO_X_DISTANCE

# Ensure heading matches the target lane’s orientation at projected position
advHeading = rightLane.orientation[rightLane.centerline.project(projectPt).coords[0]]

# Spawn the Adversarial Agent in the rightmost adjacent lane, approaching from the right
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn rightLane,
    with behavior AdvBehavior()