extends KinematicBody2D


var speed  = 65
var motion = Vector2.ZERO
var player = null

func _physics_process(delta):
	motion = Vector2.ZERO
	if player:
		motion = position.direction_to(player.position) * speed
	motion = move_and_slide(motion)
	for i in get_slide_count():
		var collision = get_slide_collision(i)
		if collision.collider.name == 'Player1':
			print('Player got bombed')
			
			
	
	
	

func _on_Area2D_body_entered(body):
	player = body


func _on_Area2D_body_exited(body):
	print('Player has exited')
	player = null
	
