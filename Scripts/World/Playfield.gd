class_name Playfield
## Shared geometry and movement constants.
##
## Values here are mirrored by Tools/campaign.py (row spacing, action spacing),
## so a validated level stays fair at the speed it was validated for.

## 2.9 m of pitch per lane, a little wider than the widest obstacle, so two
## obstacles on neighbouring lanes never visually merge into one wall.
const LANE_WIDTH := 2.9
const TRACK_WIDTH := 9.4
const LANES := [-1, 0, 1]

const GRAVITY := -34.0
const JUMP_VELOCITY := 9.6
const DOUBLE_JUMP_FACTOR := 0.94
const SLIDE_TIME := 0.62
const LONG_SLIDE_TIME := 0.95
const LANE_CHANGE_SPEED := 16.0

const STAND_HEIGHT := 1.55
const SLIDE_HEIGHT := 0.74
const PLAYER_RADIUS := 0.38
## Half the modelled body width, used so collisions include his shoulder.
const PLAYER_SHOULDER := 0.28
const PLAYER_DEPTH := 0.42

const CAMERA_BASE_FOV := 66.0
const CAMERA_SPEED_FOV := 78.0

## A finger has to travel this far before it counts as a swipe rather than a tap.
const SWIPE_THRESHOLD := 38.0


static func lane_x(lane: int) -> float:
	return float(clamp(lane, -1, 1)) * LANE_WIDTH


static func nearest_lane(x: float) -> int:
	return clampi(int(round(x / LANE_WIDTH)), -1, 1)


static func format_distance(metres: float) -> String:
	return "%d m" % int(metres)
