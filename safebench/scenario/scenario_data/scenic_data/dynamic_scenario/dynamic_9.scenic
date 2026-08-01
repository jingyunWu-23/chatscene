'''The ego vehicle is turning left at an intersection; the adversarial cyclist on the left front suddenly stops in the middle of the intersection and dismounts, obstructing the ego vehicle's path.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    do CrossingBehavior(ego, globalParameters.OPT_ADV_SPEED, globalParameters.OPT_ADV_DISTANCE) until (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    while True:
        take SetSpeedAction(0)
    take DismountAction()

param OPT_ADV_SPEED = Range(0, 10)
param OPT_ADV_DISTANCE = Range(0, 15)
param OPT_STOP_DISTANCE = Range(0, 1)
intersection = Uniform(*filter(lambda i: i.is4Way, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.LEFT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Identifying the left approach lane to the intersection (i.e., the lane that connects to the ego's current lane from the left, typically orthogonal or at an angle)
param OPT_GEO_X_DISTANCE = Range(-10, -2)   # lateral offset toward left approach
param OPT_GEO_Y_DISTANCE = Range(5, 25)      # longitudinal distance ahead along left approach

# Get the lane to the left of ego's current lane section — but for intersection entry, we prefer the *incoming* left-approach lane
# Since Scenic 2.1 does not expose direct "intersection incoming lanes", we use the left-adjacent lane section *at the intersection entrance*
# First, get ego's current lane section and its left neighbor; then project forward along that left neighbor's centerline
advLaneSec = network.laneSectionAt(ego)._laneToLeft
require advLaneSec is not None
advLane = advLaneSec.lane
# Spawn point offset along advLane’s centerline, starting from where it aligns with ego’s position laterally
IntSpawnPt = OrientedPoint following advLane.heading from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent entering or already within the intersection from the left approach lane
AdvAgent = Bicycle at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()