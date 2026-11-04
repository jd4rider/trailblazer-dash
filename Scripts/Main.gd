extends Node
## Entry point: hands the scene tree to the router.


func _ready() -> void:
	Router.boot(self)
