'''The ego vehicle is performing a lane change to evade a slow-moving vehicle; the adversarial car in the target lane on the right front suddenly brakes, causing the ego vehicle to react quickly to avoid a collision.'''
Town = 'Town03'
param map = localPath(f'../maps/{Town}.xodr') 
param carla_map = Town
model scenic.simulators.carla.model
EGO_MODEL = "vehicle.lincoln.mkz_2017"

behavior AdvBehavior():
    # Follow the lane at the defined speed until close enough to the ego vehicle
    do FollowLaneBehavior(target_speed=globalParameters.OPT_ADV_SPEED) until (distance to self) < globalParameters.OPT_ADV_DISTANCE
    # Once within the distance threshold, execute a sudden brake while remaining in the target lane
    while True:
        take SetBrakeAction(globalParameters.OPT_BRAKE)

param OPT_ADV_SPEED = Range(5, 10)  # Adversarial vehicle's cruising speed
param OPT_ADV_DISTANCE = Range(0, 20)  # Distance threshold to initiate braking
param OPT_BRAKE = Range(0, 1)  # Braking intensity, where 1 represents full braking
# Identifying lane sections with a right lane moving in the same forward direction
laneSecsWithRightLane = []
for lane in network.lanes:
    for laneSec in lane.sections:
        if laneSec._laneToRight is not None and laneSec._laneToRight.isForward == laneSec.isForward:
            laneSecsWithRightLane.append(laneSec)

# Selecting a random lane section from identified sections for the ego vehicle
egoLaneSec = Uniform(*laneSecsWithRightLane)
egoSpawnPt = OrientedPoint in egoLaneSec.centerline

# Ego vehicle setup
ego = Car at egoSpawnPt,
    with regionContainedIn None,
    with blueprint EGO_MODEL
# Identifying the adjacent lane for the Adversarial Agent and setting its spawn point further in front
param OPT_GEO_Y_DISTANCE = Range(0, 30)
advLaneSec = network.laneSectionAt(ego)._laneToRight
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)._laneToLeft
if advLaneSec is None:
    advLaneSec = network.laneSectionAt(ego)
require advLaneSec is not None
advLane = advLaneSec.lane
IntSpawnPt = OrientedPoint following roadDirection from egoSpawnPt for globalParameters.OPT_GEO_Y_DISTANCE
projectPt = Vector(*advLane.centerline.project(IntSpawnPt.position).coords[0])
advHeading = advLane.orientation[projectPt]

# Spawn the Adversarial Agent
AdvAgent = Car at projectPt,
    with heading advHeading,
    with regionContainedIn None,
    with behavior AdvBehavior()