'''The ego vehicle is moving straight through the intersection; the adversarial agent, initially on the left front, runs the red light and makes an abrupt right turn, forcing the ego vehicle to perform a collision avoidance maneuver.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is within a threatening proximity.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance from self to egoTrajectory) < globalParameters.OPT_STEER_DISTANCE
    # Once close to the ego's trajectory, the adversarial vehicle initiates a sharp right turn while running the red light.
    while True:
        take SetSpeedAction(self.speed)  # Continues moving at its current speed
        take SetSteerAction(globalParameters.OPT_STEER)  # Makes an abrupt right steering adjustment

param OPT_ADV_SPEED = Range(5, 15)  # The speed at which the adversarial vehicle approaches the intersection (running the red light).
param OPT_STEER_DISTANCE = Range(0, 4)  # Distance from ego's trajectory at which the vehicle starts to turn.
param OPT_STEER = Range(0.5, 1.0)  # Defines the intensity of the right steering action.

## MONITORS
monitor TrafficLights:
    freezeTrafficLights()
    while True:
        if withinDistanceToTrafficLight(ego, 100):
            setClosestTrafficLightStatus(ego, "green")
        if withinDistanceToTrafficLight(AdvAgent, 100):
            setClosestTrafficLightStatus(AdvAgent, "red")
        wait

intersection = Uniform(*filter(lambda i: i.is4Way and i.isSignalized, network.intersections))
egoInitLane = Uniform(*intersection.incomingLanes)
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.STRAIGHT, egoInitLane.maneuvers))
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoManeuver.startLane.centerline

# Setting up the ego vehicle at the initial position
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Identify the left-leg cross street (i.e., road perpendicular to ego's direction, entering from the left)
# First, get the ego's current lane section and its left-adjacent road (cross street entering from left)
egoLaneSection = network.laneSectionAt(ego)
# In Scenic 2.1, `_laneToLeft` gives adjacent lane *in same road*; for intersection legs, we need connected road.
# Instead, use `network.roadsAt` to find roads intersecting at ego's location, then select the one oriented ~leftward relative to ego's heading.
egoPos = egoSpawnPt.position
intersectingRoads = network.roadsAt(egoPos)
# Find road whose heading is approximately ego's heading - 90 deg (i.e., coming from left, traveling toward ego's path)
# We assume the left-leg cross street is the one whose centerline near ego has orientation ≈ egoSpawnPt.heading - 90 deg
# Since Scenic 2.1 doesn't support direct angle filtering in expressions, we rely on topology: use the road connected via left junction
# Standard pattern: use `egoLaneSection.leftJunction` if available; otherwise fall back to geometric selection.
# Per CARLA/Scenic conventions, prefer using `network.laneSectionAt(...).leftJunction.connectedRoads[0]` if junction exists.
# But since junction access isn't guaranteed, use robust fallback: project ego position onto candidate roads and pick road with normal ~left.

# Instead, use standard Scenic 2.1 idiom for cross-street left leg: find road whose centerline has dominant y-component opposite to ego's lateral direction
# Simpler & consistent with examples: use `network.laneSectionAt(ego)._laneToLeft.lane` only for same-road lanes — not applicable here.
# Correct approach: use `network.roadsAt(egoPos)` and filter by orientation relative to egoSpawnPt.heading.

# However, Scenic 2.1 does not support runtime filtering of `roadsAt` by angle in static scene definition.
# So we follow common practice in Scenic benchmarks: assume a pre-defined "leftCrossRoad" exists or use geometric proxy.

# Since description says "approaching the intersection from the left leg", meaning the adversarial agent is on a *different road*, traveling straight on that road, then turning right into ego's lane.
# Thus, its spawn point should be on that cross road, upstream (i.e., before intersection), heading toward the intersection.

# We define:
param OPT_CROSS_DISTANCE = Range(15, 45)  # distance along cross road upstream from intersection
param OPT_CROSS_SPEED = Range(3, 8)

# Get intersection point: approximate as egoSpawnPt projected onto nearest junction or road intersection
# Use egoSpawnPt as proxy; find closest point on any road perpendicular to ego's heading
# Scenic 2.1 provides `network.nearestIntersectionTo`, but it's not in base API — instead use `network.intersectionsAt`
# Since `intersectionsAt` may be unavailable, use fallback: ego's current road's centerline intersection with its left-connected road.

# Robust & idiomatic Scenic 2.1 approach: use `network.laneSectionAt(ego).leftJunction` if present, else use `egoSpawnPt` as intersection proxy.
# But to avoid undefined behavior, assume existence of `leftCrossLane` via topology — standard in CARLA maps.

# Instead, follow pattern used in official Scenic CARLA examples: use `network.laneSectionAt(ego).leftJunction.connectedRoads[0].centerline` if junction exists,
# else fall back to manually constructed perpendicular offset.

# Given constraints and consistency with prior snippets, we construct spawn point by:
# 1. Taking egoSpawnPt
# 2. Moving left (i.e., egoSpawnPt.heading - 90 deg) by a fixed offset to reach left-leg road centerline
# 3. Then moving *forward along that cross road* (i.e., along heading ≈ egoSpawnPt.heading - 90 deg) by OPT_CROSS_DISTANCE

# This matches "approaching from left leg": agent is on left-side cross street, moving toward intersection → so its heading ≈ egoSpawnPt.heading - 90 deg, position upstream along that direction.

param OPT_LATERAL_OFFSET = Range(2, 6)  # distance to shift left to reach cross street centerline
param OPT_UPSTREAM_DISTANCE = Range(15, 45)  # distance along cross street before intersection

# Compute leftward offset vector
leftDir = Vector(cos(egoSpawnPt.heading - 90 deg), sin(egoSpawnPt.heading - 90 deg))
crossCenterlinePt = egoSpawnPt.position + leftDir * globalParameters.OPT_LATERAL_OFFSET

# Now move upstream along cross street (i.e., direction of adversarial agent's motion: toward intersection → same as egoSpawnPt.heading - 90 deg)
# So spawn point is upstream: from crossCenterlinePt, go *opposite* to agent's travel direction → i.e., backward along -90 deg heading
# But "approaching from left leg" means agent is coming *from* the left and moving *toward* ego's path → so its velocity vector points ≈ egoSpawnPt.heading - 90 deg.
# Therefore, to place it *before* intersection, we go *against* that direction from intersection proxy.

# Use egoSpawnPt as intersection proxy; so upstream point = egoSpawnPt.position + leftDir * globalParameters.OPT_LATERAL_OFFSET - leftDir * globalParameters.OPT_UPSTREAM_DISTANCE
# = egoSpawnPt.position + leftDir * (OPT_LATERAL_OFFSET - OPT_UPSTREAM_DISTANCE) → no, that’s collinear.

# Correct: agent travels *along* leftDir direction toward ego’s lane → so to place it upstream, start at egoSpawnPt.position, shift left to cross street, then move *further left* (i.e., continue along leftDir) by OPT_UPSTREAM_DISTANCE? No — that would be parallel, not upstream.

# Actually: if ego is going along x-axis (heading 0°), left is -y direction. Cross street is vertical (y-axis), agent travels *up* (+y) toward intersection at (x,0). So upstream is at (x, -d). So position = egoSpawnPt.position + Vector(0,-d) = egoSpawnPt.position + leftDir * d.

# Yes: leftDir = (cos(-90°), sin(-90°)) = (0,-1); so moving by leftDir * d goes downward — which is upstream if intersection is at y=0 and agent moves upward.

# So spawn point = egoSpawnPt.position + leftDir * globalParameters.OPT_UPSTREAM_DISTANCE + leftDir * globalParameters.OPT_LATERAL_OFFSET? No — lateral offset gets us *to* cross street; upstream is *along* cross street, i.e., same direction.

# Thus: crossCenterlinePt = egoSpawnPt.position + leftDir * globalParameters.OPT_LATERAL_OFFSET  
# Then AdvSpawnPt = crossCenterlinePt + leftDir * globalParameters.OPT_UPSTREAM_DISTANCE  
# But that places it further left, not upstream *along* cross street toward intersection.

# Wait: if ego is at (0,0) heading 0° (east), left is north? No: in Scenic, angles increase counterclockwise; heading 0° is east (x+), 90° is north (y+), -90° is south (y−).  
# Standard CARLA/Scenic: forward = +x, left = +y (i.e., heading +90°), right = -y. So leftDir = Vector(cos(egoSpawnPt.heading + 90 deg), sin(egoSpawnPt.heading + 90 deg))

# Clarify: Scenic uses mathematical angles: 0° = east, 90° = north. So "left" of heading θ is direction θ + 90°.

# Therefore: leftDir = Vector(cos(egoSpawnPt.heading + 90 deg), sin(egoSpawnPt.heading + 90 deg))

# And agent on left-leg cross street traveling *toward intersection* has heading = egoSpawnPt.heading + 90 deg (i.e., north if ego heads east).

# So upstream (starting point before intersection) is *south* of intersection → i.e., opposite direction: egoSpawnPt.heading - 90 deg.

# So: crossCenterlinePt = egoSpawnPt.position + leftDir * globalParameters.OPT_LATERAL_OFFSET  
# Then move *backward* along agent's travel direction (i.e., -leftDir) by OPT_UPSTREAM_DISTANCE to get upstream spawn.

# Thus: AdvSpawnPt = crossCenterlinePt - leftDir * globalParameters.OPT_UPSTREAM_DISTANCE  
# = egoSpawnPt.position + leftDir * (OPT_LATERAL_OFFSET - OPT_UPSTREAM_DISTANCE)

# But OPT_UPSTREAM_DISTANCE > OPT_LATERAL_OFFSET typically, so this goes beyond ego — not desired.

# Better: define intersection point as projection of egoSpawnPt onto left cross road centerline. But Scenic 2.1 `project` requires a centerline.

# Given complexity and need for consistency with examples, use simplest safe construction matching semantics:

# "Adversarial agent is initially on the left front of the ego vehicle, approaching the intersection from the left leg"  
# → It must be *in front* (i.e., ahead of ego along ego's direction) *and* to the left → so position is egoSpawnPt.position + forwardVec * d_forward + leftVec * d_left  
# with d_forward > 0, d_left > 0.

# That matches "left front" spatially — same as first example, but now agent is *not* in adjacent lane of same road, but on crossing road.

# So:  
# forwardVec = Vector(cos(egoSpawnPt.heading), sin(egoSpawnPt.heading))  
# leftVec = Vector(cos(egoSpawnPt.heading + 90 deg), sin(egoSpawnPt.heading + 90 deg))  
# AdvSpawnPt = egoSpawnPt.position + forwardVec * globalParameters.OPT_GEO_X_DISTANCE + leftVec * globalParameters.OPT_GEO_Y_DISTANCE  

# And heading = egoSpawnPt.heading + 90 deg (traveling straight on cross street toward intersection, then will turn right into ego's lane).

# This is clean, uses only Scenic 2.1 primitives, and matches "left front" spatially while encoding intent.

param OPT_GEO_X_DISTANCE = Range(5, 25)   # forward distance (along ego's direction)
param OPT_GEO_Y_DISTANCE = Range(2, 8)    # left distance (to cross street)

forwardVec = Vector(cos(egoSpawnPt.heading), sin(egoSpawnPt.heading))
leftVec = Vector(cos(egoSpawnPt.heading + 90 deg), sin(egoSpawnPt.heading + 90 deg))
AdvSpawnPt = egoSpawnPt.position + forwardVec * globalParameters.OPT_GEO_X_DISTANCE + leftVec * globalParameters.OPT_GEO_Y_DISTANCE

AdvAgent = Car at AdvSpawnPt,
    with heading egoSpawnPt.heading + 90 deg,
    with regionContainedIn None,
    with behavior AdvBehavior()