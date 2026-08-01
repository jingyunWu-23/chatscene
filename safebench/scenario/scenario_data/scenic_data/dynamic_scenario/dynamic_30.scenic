'''The ego is performing a right turn at an intersection when the crossing car suddenly speeds up, entering the intersection and causing the ego to brake abruptly to avoid a collision.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to impact the ego's maneuver.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance to self) < globalParameters.OPT_ADV_DISTANCE
    # Abruptly accelerates to enter the intersection.
    while True:
        take SetThrottleAction(globalParameters.OPT_THROTTLE)

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection.
param OPT_ADV_DISTANCE = Range(5, 20)  # The critical distance at which the adversarial begins to accelerate.
param OPT_THROTTLE = Range(0.5, 1.0)  # The intensity of the throttle during acceleration.
intersection = Uniform(*filter(lambda i: i.is4Way and i.isSignalized, network.intersections))
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.RIGHT_TURN, intersection.maneuvers))
egoInitLane = egoManeuver.startLane
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoInitLane.centerline

ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_X_DISTANCE = Range(-10, 0)   # Lateral offset from ego's path (left side, negative x in ego frame)
param OPT_GEO_Y_DISTANCE = Range(-5, 5)    # Longitudinal offset relative to intersection boundary (just before)

# Determine the intersection boundary: find the nearest intersection ahead of ego and get its boundary
# In Scenic 2.1, we use `network.intersectionAt` or project onto road geometry; since exact intersection API may vary,
# we approximate using the ego's current lane section and its lateral left extension near the upcoming junction.
laneSec = network.laneSectionAt(ego)
leftLaneSec = laneSec._laneToLeft
require leftLaneSec is not None
leftLane = leftLaneSec.lane

# Compute a point just before the intersection: use egoSpawnPt offset laterally left and slightly forward/backward
# We interpret "just before the intersection boundary" as a point on the left-lane centerline aligned with ego's longitudinal position,
# but shifted laterally left and adjusted longitudinally to be at the intersection ingress.
# Since Scenic 2.1 does not expose direct intersection boundary queries, we construct spawn point perpendicular to ego's direction:
# Use egoSpawnPt offset left (perpendicular to roadDirection) by OPT_GEO_X_DISTANCE, then project onto leftLane.
PerpOffset = globalParameters.OPT_GEO_X_DISTANCE @ 0
LateralSpawnPt = egoSpawnPt offset left by PerpOffset

# Project onto left lane to ensure valid position
projected = leftLane.centerline.project(LateralSpawnPt.position)
projectPt = Vector(*projected.coords[0])
advHeading = leftLane.orientation[projectPt]

# Optional: fine-tune longitudinal position to be "just before intersection" — shift along left lane's direction
# We apply small longitudinal adjustment (OPT_GEO_Y_DISTANCE) *along* leftLane’s local heading (not ego’s)
# Since leftLane orientation may differ, we use advHeading to move forward along that lane
# Scenic 2.1 supports `offset along heading by d`, so:
IntSpawnPt = OrientedPoint at projectPt with heading advHeading
AdvSpawnPt = IntSpawnPt offset along advHeading by globalParameters.OPT_GEO_Y_DISTANCE

# Spawn the Adversarial Agent
AdvAgent = Car at AdvSpawnPt.position,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()