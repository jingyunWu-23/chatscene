'''The ego approaches a parked car that is blocking its lane and must use the opposite lane to bypass the vehicle, cautiously monitoring oncoming traffic, and suddenly encounters a jaywalking pedestrian, requiring the ego to quickly assess the situation and respond appropriately to avoid a collision.'''
Town = 'Town01'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    # Determine oncoming lane: opposite direction to ego's heading, offset laterally
    oncomingLane = ego.lane.offsetLateral(ego.lane.width)  # Approximate opposite-direction lane
    targetPoint = oncomingLane.centerline.pointAtDistance(globalParameters.OPT_ADV_DISTANCE)
    
    # Wait until ego is within triggering distance
    while (distance to self) > globalParameters.OPT_ADV_DISTANCE:
        wait
    
    # Walk directly toward target point in oncoming lane (jaywalking across traffic)
    while True:
        take SetWalkingDirectionAction(direction from self to targetPoint)
        take SetWalkingSpeedAction(globalParameters.OPT_ADV_SPEED)

param OPT_ADV_SPEED = Range(0, 5)
param OPT_ADV_DISTANCE = Range(0, 15)
# Collecting lane sections that have a left lane (opposite traffic direction) and no right lane (single forward road)
laneSecsWithLeftLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec._laneToLeft is not None and laneSec._laneToRight is None:
            if laneSec._laneToLeft.isForward != laneSec.isForward:
                laneSecsWithLeftLane.append(laneSec)

# Selecting a random lane section that matches the criteria
egoLaneSec = Uniform(*laneSecsWithLeftLane)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Parameters for scenario elements
param OPT_GEO_BLOCKER_Y_DISTANCE = Range(0, 40)
param OPT_GEO_X_DISTANCE = Range(-2, 2)
param OPT_GEO_Y_DISTANCE = Range(2, 6)

# Setup for the blocking car that the ego must bypass
laneSec = network.laneSectionAt(ego)
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_BLOCKER_Y_DISTANCE
Blocker = Car at IntSpawnPt,
    with heading IntSpawnPt.heading,
    with regionContainedIn None

# Setup for the adversarial agent emerging from the right sidewalk into the opposite (oncoming) lane
# Right side relative to ego's original direction → positive lateral offset perpendicular to heading
SHIFT = globalParameters.OPT_GEO_X_DISTANCE @ globalParameters.OPT_GEO_Y_DISTANCE
AdvAgent = Pedestrian at Blocker offset along IntSpawnPt.heading by SHIFT,
    with heading IntSpawnPt.heading + 90 deg,  # Facing perpendicular to road — crossing *from right sidewalk*
    with regionContainedIn laneSec._laneToLeft,  # Entering the left/oncoming lane (opposite to ego's original lane)
    with behavior AdvBehavior()