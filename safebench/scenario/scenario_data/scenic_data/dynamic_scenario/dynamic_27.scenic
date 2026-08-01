'''The ego commences an unprotected left turn at an intersection while yielding to an oncoming car when the adversarial car, comes from the right, blocks multiple lanes by driving extremely slowly, forcing the ego vehicle to change lanes.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while True:
        take SetSpeedAction(globalParameters.OPT_SLOW_SPEED)  # Maintains an extremely slow speed to block lanes.
        # Optionally, introduce minor lateral variation to span multiple lanes (e.g., gentle swerving within or across adjacent lanes)
        if len(network.laneSectionAt(self).adjacentLanes) > 0:
            targetLaneSec = network.laneSectionAt(self).adjacentLanes[0]
            do LaneChangeBehavior(laneSectionToSwitch=targetLaneSec, target_speed=globalParameters.OPT_SLOW_SPEED)
        # Wait a variable number of steps before next potential lane adjustment
        for _ in range(globalParameters.OPT_WAIT_LANE_CHANGE):
            wait

param OPT_SLOW_SPEED = Range(0, 2)  # Extremely slow speed to impede traffic flow.
param OPT_WAIT_LANE_CHANGE = Range(10, 50)  # Time between lane-blocking adjustments.

## MONITORS
monitor TrafficLights:
    freezeTrafficLights()
    while True:
        if withinDistanceToTrafficLight(ego, 100):
            setClosestTrafficLightStatus(ego, "green")
        if withinDistanceToTrafficLight(AdvAgent, 100):
            setClosestTrafficLightStatus(AdvAgent, "green")
        wait

intersection = Uniform(*filter(lambda i: i.is4Way and i.isSignalized, network.intersections))
egoInitLane = Uniform(*intersection.incomingLanes)
egoManeuver = Uniform(*filter(lambda m: m.type is ManeuverType.LEFT_TURN, egoInitLane.maneuvers))
egoTrajectory = [egoInitLane, egoManeuver.connectingLane, egoManeuver.endLane]
egoSpawnPt = OrientedPoint in egoManeuver.startLane.centerline

# Setting up the ego vehicle at the initial position
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Parameters for scenario elements
param OPT_GEO_X_DISTANCE = Range(0, 15)      # Distance along ego's right (i.e., perpendicular to ego's forward direction)
param OPT_GEO_Y_DISTANCE = Range(-10, 5)      # Slight offset along ego's forward direction (to position at intersection)
param OPT_BLOCKER_Y_DISTANCE = Range(0, 5)    # For optional blocker placement in ego's lane if needed (not required per description, but kept minimal if used)

# Identify the intersecting road to the right of ego
# In Scenic 2.1, we use network.laneSectionAt(ego) and its _laneToRight to get adjacent lanes,
# but for an *intersecting* road coming from the right, we rely on the network’s connectivity.
# Since Scenic 2.1 does not expose explicit intersection geometry via `network`, we instead
# assume the ego is approaching an intersection and that the "right-coming" adversarial agent
# spawns on a lane whose centerline is approximately perpendicular to ego's direction and lies to ego's right.

# Get ego's current lane section and its rightmost lane(s) — but here, "rightmost lane(s) of the road intersecting the ego’s path — coming from the right"
# implies a *cross street*, so we use the standard CARLA/Scenic convention: lanes orthogonal to ego's heading, accessible via network's lane sections near ego.
# We approximate by sampling a point to the right of ego, then finding the nearest lane with heading ~90 deg offset (i.e., crossing).

# Compute spawn point in ego's local right direction (perpendicular to roadDirection)
# Note: roadDirection is the forward direction of ego's lane; right is rotated -90 deg
rightDir = rotateVector(roadDirection, -90 deg)
IntSpawnPt = OrientedPoint at (egoSpawnPt.position + rightDir * globalParameters.OPT_GEO_X_DISTANCE),
    with heading rotateVector(roadDirection, 90 deg)  # Adversarial agent comes *from the right*, so its heading is ~+90 deg (i.e., toward ego's forward direction)

# Find the nearest lane to IntSpawnPt that is part of a *crossing* road (i.e., roughly orthogonal).
# Since Scenic 2.1 doesn’t provide direct intersection lane lookup, we use the most robust fallback:
# project onto the nearest lane whose orientation is within ±30 deg of IntSpawnPt.heading
# But per examples, we instead use laneSectionAt(ego)._laneToRight.lane as proxy *only if it's orthogonal* — however, that’s adjacent, not intersecting.

# Instead, follow pattern from third example: use offset-based spawn relative to ego, then constrain to a lane region.
# The description says "rightmost lane(s) of the road intersecting", implying multiple lanes — so we target the *rightmost traversable lane* of the cross street.
# In CARLA + Scenic 2.1, cross-street lanes are often modeled as `_laneToRight` of the *intersection lane section*, but since we lack explicit intersection object,
# we conservatively assume the adversarial agent spawns on a lane accessible via `network.laneAt(IntSpawnPt.position)` — and require it to be orthogonal.

# Safe fallback (consistent with Scenic 2.1 idioms & examples): use `network.laneAt` and filter by heading alignment.
candidateLanes = [lane for lane in network.lanesAt(IntSpawnPt.position)
                  if abs(angleBetween(lane.orientation[IntSpawnPt.position], IntSpawnPt.heading)) < 45 deg]
advLane = candidateLanes[0] if len(candidateLanes) > 0 else network.laneAt(IntSpawnPt.position)

# Project spawn point onto advLane centerline to ensure validity
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent — occupying *multiple adjacent lanes*, so we set regionContainedIn to the union of rightmost lanes
# Per description: "rightmost lane(s)" → get rightmost lane(s) of the cross road. In Scenic 2.1, we can access `_laneToRight` chain.
# Start from advLane and walk right until no more right lane — collect all.
rightmostLanes = [advLane]
cur = advLane
while cur._laneToRight is not None:
    curSec = cur._laneToRight
    if curSec is None:
        curSec = cur._laneToLeft
    if curSec is None:
        curSec = cur
    require curSec is not None
    cur = curSec.lane
    rightmostLanes.append(cur)
# Use the union of those lanes as containment region
advRegion = UnionRegion(rightmostLanes)

# Spawn adversarial car
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn advRegion,
    with behavior AdvBehavior()
