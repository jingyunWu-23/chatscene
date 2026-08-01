'''The ego vehicle is changing to the right lane; the adversarial car is driving parallel to the ego and blocking its path.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while True:
        take SetVelocityAction(*ego.velocity)  # Match ego's velocity to drive parallel.
        # Actively block lane changes by adjusting lateral position to stay in the same lane section as ego,
        # or shift laterally to occupy adjacent lane if ego attempts to change lanes.
        take SetPositionAction(ego.position + Vector(0, globalParameters.OPT_BLOCK_OFFSET, 0))
        wait

param OPT_BLOCK_OFFSET = Range(-2, 2)  # Lateral offset (in meters) to maintain blocking position relative to ego; negative = left, positive = right.
# Identifying lane sections with at least two adjacent lanes in the same direction
laneSecsWithTwoAdjacent = []
for lane in network.lanes:
    for laneSec in lane.sections:
        leftCount = 0
        rightCount = 0
        if laneSec._laneToLeft is not None and laneSec._laneToLeft.isForward == laneSec.isForward:
            leftCount = 1
        if laneSec._laneToRight is not None and laneSec._laneToRight.isForward == laneSec.isForward:
            rightCount = 1
        if leftCount + rightCount >= 2:
            laneSecsWithTwoAdjacent.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
egoLaneSec = Uniform(*laneSecsWithTwoAdjacent)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Identifying the adjacent lane to the right for the Adversarial Agent and setting its spawn point laterally aligned with ego
param OPT_LATERAL_OFFSET = Range(0, 5)
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = egoLaneSec
require advLaneSec is not None
advLane = advLaneSec
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for 0
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()