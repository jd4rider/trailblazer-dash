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

## Jump arc, sized against the obstacles rather than by feel. A hurdle's hit band
## stops at 1.03 m, so his feet have to be above that for the whole 2.1 m band,
## which is 0.26 s at the slowest level and 0.16 s at the fastest. These numbers
## keep him above 1.03 m for 0.55 s and above a pit lip for 0.64 s, leaving about
## +/-0.2 s of timing slack. The previous -34/9.6 pair cleared the rail for 0.28 s
## only, i.e. under one frame of slack: jumping at a hurdle still always hit it.
const GRAVITY := -30.0
const JUMP_VELOCITY := 11.4
const DOUBLE_JUMP_FACTOR := 0.94
## A jump tops out here. Well clear of a 1.03 m hurdle, but under the 2.95 m train
## roof, so a stacked double jump can never carry him over a train.
const JUMP_CEILING := 2.4
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
## Too low and a normal thumb wobble reads as a flick.
const SWIPE_THRESHOLD := 48.0
## A drag counts as horizontal only when it is clearly wider than it is tall, so
## a diagonal flick cannot both change lane and jump.
const SWIPE_AXIS_RATIO := 1.35
## Movement under this is a tap (jump), not a swipe.
const TAP_SLOP := 24.0


static func lane_x(lane: int) -> float:
	return float(clamp(lane, -1, 1)) * LANE_WIDTH


static func nearest_lane(x: float) -> int:
	return clampi(int(round(x / LANE_WIDTH)), -1, 1)


static func format_distance(metres: float) -> String:
	return "%d m" % int(metres)
