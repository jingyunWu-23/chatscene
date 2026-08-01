'''The ego encounters a parked car blocking its lane and must use the opposite lane to bypass the vehicle when an oncoming pedestrian enters the lane without warning and suddenly stop, necessitating the ego to brake sharply or steer to avoid hitting the pedestrian.'''
Town = 'Town01'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    initialHeading = self.heading
    # Rotate 180° to enter the opposite (oncoming) lane
    take SetHeadingAction(initialHeading + 180 deg)
    # Start moving toward oncoming lane (assume lateral movement across lanes; use walking speed forward in new heading)
    take SetWalkingSpeedAction(globalParameters.OPT_ADV_SPEED)
    # Move for a short duration before stopping abruptly
    for _ in range(globalParameters.OPT_MOVE_STEP):
        wait
    while True:
        take SetWalkingSpeedAction(0)

param OPT_ADV_SPEED = Range(1, 5)
param OPT_MOVE_STEP = Range(1, 20)
# Collecting lane sections that have a left lane (opposite traffic direction) and no right lane (single forward road)
laneSecsWithLeftLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec._laneToLeft is not None and laneSec._laneToRight is None:
            if laneSec._laneToLeft.isForward != laneSec.isForward:
                laneSecsWithLeftLane.append(laneSec)

# Selecting a random lane section that matches the criteria
if len(laneSecsWithLeftLane) == 0:
    laneSecsWithLeftLane = network.laneSections
egoLaneSec = Uniform(*laneSecsWithLeftLane)
if egoLaneSec is None:
    egoLaneSec = Uniform(*network.laneSections)
require egoLaneSec is not None
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_Y_DISTANCE = Range(10, 30)
param OPT_GEO_X_DISTANCE = Range(-4, 4)  # Small lateral offset to place in oncoming lane center

# Identify the oncoming lane: since ego has entered the opposite lane to bypass a parked car,
# the oncoming lane is the one ego is now occupying — i.e., the lane *to the left* of ego's original lane.
# We assume egoSpawnPt is in the original (rightmost/directional) lane, and ego has moved left.
# So the oncoming lane relevant for the adversarial agent is ego's *current* lane — but we must derive it safely.
# Following pattern from first example: use laneSectionAt(ego) to get current context, then _laneToLeft is the true oncoming lane *if ego is in right lane*.
# However, description says adversarial agent emerges "from the front-left of the ego vehicle — directly in the opposite (oncoming) lane that the ego has entered".
# So ego is *already in* the opposite (e.g., left/center) lane; thus the oncoming traffic lane is the one ego is *currently in*, and the adversarial agent spawns ahead in *that same lane*, facing opposite direction.

# To be consistent with Scenic 2.1 idioms and prior examples, we treat the adversarial agent as spawning in the *same lane ego currently occupies*, but heading opposite (i.e., oncoming).
# Since ego’s current lane is not trivially available without ego being spawned, and per examples, we rely on network.laneSectionAt(ego) to get local lane structure.
laneSec = network.laneSectionAt(ego)
if laneSec is None:
    laneSec = egoLaneSec
require laneSec is not None
# The lane ego is *in* is laneSec.lane; but for oncoming traffic, we want the *same geometric lane*, just opposite heading.
# So we spawn ahead along roadDirection, then flip heading.

IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE

# Spawn adversarial agent in the *same* lane ego is in (i.e., regionContainedIn laneSec.lane), facing opposite direction
AdvAgent = Pedestrian at IntSpawnPt,
    with heading IntSpawnPt.heading + 180 deg,
    with regionContainedIn laneSec,
    with behavior AdvBehavior()
