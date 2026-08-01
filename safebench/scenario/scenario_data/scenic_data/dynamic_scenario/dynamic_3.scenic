'''The ego vehicle is driving on a straight road; the adversarial pedestrian appears from a driveway on the left and suddenly stop and walk diagonally.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    direction = self.heading + globalParameters.OPT_ADV_DEGREE deg
    while (distance to self) > globalParameters.OPT_ADV_DISTANCE:
        wait
    while True:
        take SetWalkingDirectionAction(direction)
        take SetWalkingSpeedAction(globalParameters.OPT_ADV_SPEED) until (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
        take SetWalkingSpeedAction(0)

param OPT_ADV_SPEED = Range(0, 5)
param OPT_ADV_DISTANCE = Range(0, 15)
param OPT_ADV_DEGREE = Range(-90, 90)
param OPT_STOP_DISTANCE = Range(0, 1)
# Selecting a straight road segment (lane section with negligible curvature)
straightLaneSections = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec.centerline.isStraight:
            straightLaneSections.append(laneSec)

if len(straightLaneSections) == 0:
    straightLaneSections = network.laneSections
egoLaneSec = Uniform(*straightLaneSections)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
param OPT_GEO_X_DISTANCE = Range(-15, -5)  # Left side, offset from road edge into driveway
param OPT_GEO_Y_DISTANCE = Range(10, 40)

# Get the left roadside (driveway access point) — use lane’s left boundary or adjacent sidewalk/driveway region
# In Scenic 2.1, driveways are typically modeled as regions adjacent to road; we approximate via offset left of ego’s lane centerline
egoLane = network.laneSectionAt(egoSpawnPt)._lane
leftBoundary = egoLane.leftEdge
# Project a point forward along road direction, then offset perpendicularly left into driveway
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
drivewayOffset = Vector(leftBoundary.offsetDirection * globalParameters.OPT_GEO_X_DISTANCE)
drivewaySpawnPos = IntSpawnPt.position + drivewayOffset

AdvAgent = Pedestrian at drivewaySpawnPos,
    with heading IntSpawnPt.heading,  # Driveway agent typically enters road aligned with road direction
    with regionContainedIn None,
    with behavior AdvBehavior()