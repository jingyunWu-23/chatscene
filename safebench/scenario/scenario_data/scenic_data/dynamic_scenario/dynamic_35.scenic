'''The ego vehicle is approaching the intersection; the adversarial car (on the left) suddenly accelerates and enters the intersection first and suddenly stop.'''
Town = 'Town05'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    while (distance to self) > 60:
        wait  # The adversarial vehicle waits until it is close enough to be a threat.
    do FollowTrajectoryBehavior(globalParameters.OPT_ADV_SPEED, advTrajectory) until (distance to self) < globalParameters.OPT_ADV_DISTANCE or (distance from self to egoTrajectory) < globalParameters.OPT_STOP_DISTANCE
    # Accelerates into the intersection.
    while (distance from self to egoTrajectory) > globalParameters.OPT_STOP_DISTANCE:
        take SetThrottleAction(globalParameters.OPT_THROTTLE)  # Increase throttle to accelerate.
    while True:
        take SetSpeedAction(0)  # Abruptly stops.

param OPT_ADV_SPEED = Range(5, 15)  # Speed at which the adversarial vehicle approaches before acceleration.
param OPT_ADV_DISTANCE = Range(0, 20)  # Distance threshold to start aggressive acceleration.
param OPT_THROTTLE = Range(0.5, 1)  # Throttle level for sudden acceleration.
param OPT_STOP_DISTANCE = Range(0, 2)  # Distance from ego's trajectory at which to stop abruptly.

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
egoSpawnPt = OrientedPoint in egoInitLane.centerline

# Setting up the ego vehicle at the initial position, approaching the intersection
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL

require 10 <= (distance to intersection) <= 40
# Identifying the left-leg road (perpendicular to ego's direction) for the Adversarial Agent
param OPT_GEO_X_DISTANCE = Range(-15, -5)  # Distance along ego's heading (back from intersection)
param OPT_GEO_Y_DISTANCE = Range(-3, 3)    # Lateral offset to align with left-leg lane center

# Get the ego's current lane section and its left-connected road (i.e., the "left leg" of intersection)
egoLaneSection = network.laneSectionAt(ego)
# Assuming standard CARLA OpenDrive topology: _laneToLeft may connect to a perpendicular road via junction;
# but more robustly, we use the *connected road* to the left at the intersection — Scenic 2.1 provides `road.left` for adjacent road in junction context.
# Since `egoLaneSection._laneToLeft` is used in prior examples for adjacent *lane*, and here we need the *perpendicular road*,
# we instead use the junction-based left-approach road. In Scenic 2.1, `network.roadAt(ego).left` gives the road to the left (i.e., intersecting perpendicularly).
# However, if that’s not available or ambiguous, fallback is to use the lane’s *opposing* or *junction-connected* road — but per examples and CARLA+Scenic 2.1 conventions,
# the canonical way is: get the road the ego is on, then its `left` attribute (which refers to the road entering from the left at the intersection).

egoRoad = network.roadAt(ego)
leftLegRoad = egoRoad.left
# Ensure leftLegRoad exists; if not, fall back to lane-based left (but description specifies *perpendicular intersection leg*, so `road.left` is correct)
require leftLegRoad != None

# Sample a point near the end of the left-leg road (i.e., where it enters the intersection)
IntSpawnPt = leftLegRoad.centerline.end

# Offset slightly backward (along leftLegRoad's heading) to place agent *approaching* (not already in intersection)
# Since leftLegRoad.heading points *into* the intersection (by Scenic convention), we go backward: opposite heading
SHIFT_BACK = globalParameters.OPT_GEO_X_DISTANCE @ 0
BackOffsetPt = IntSpawnPt offset along IntSpawnPt.heading by SHIFT_BACK

# Project onto leftLegRoad's centerline to ensure validity
projected = Vector(*leftLegRoad.centerline.project(BackOffsetPt.position).coords[0])
advHeading = leftLegRoad.orientation[projected]

# Spawn the Adversarial Agent
AdvAgent = Car at projected,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()