extends Node2D

onready var main = get_parent()
onready var grid_manager = $GridManager 
onready var finish = $Finish/Area2D
onready var score_screen = $ScoreScreen

var showing_selector = false

var first_player = true

var used_spawns = []

var selected_placeables = []
var is_placing: bool
var is_selecting: bool

var game_finished = false

func end_level():
    game_finished = true
    for p in main.players:
        p.score_total = 0
        p.reset()
    EventHandler.emit_signal("scene_changed", "sawmill", "hub")
    for p in main.players:
        p.reset()

func _process(delta):
    if is_placing or is_selecting:
        for i in len(main.players):
            var player = main.players[i]
            var cursor = main.cursors[i]
            var cursor_move_delta = player.get_cursor_movement_vector().normalized() if i == 0 else player.get_cursor_movement_vector()
            cursor_move_delta *= cursor.speed * delta
            if player.is_cursor_sprinting():
                cursor_move_delta *= 2.5
            cursor.translate(cursor_move_delta)

            if is_placing:
                var placeable = selected_placeables[i]
                if placeable == null:
                    continue

                grid_manager.clamp_placeable(placeable, cursor.global_position)
                if player.select_input():
                    EventHandler.emit_signal("player_try_place", player, placeable, cursor.global_position)
                elif player.rotate_cw():
                    placeable.rotate_shape(Rotation.CLOCKWISE)
                elif player.rotate_ccw():
                    placeable.rotate_shape(Rotation.COUNTER_CLOCKWISE)
            if is_selecting:
                if player.select_input():
                    EventHandler.emit_signal("player_select_input", player, cursor.global_position)

func next_round():
    yield(handle_selection_and_placement(), "completed")
    $MapKillBounds/DownBounds.disabled = false
    
    finish.player_count = 0
    
    used_spawns = []
    first_player = true
    for p in main.players:
        p.reset()
        spawn_player(p)
        $MultiCam.add_target(p)

func handle_selection_and_placement():
    var player_count = len(main.players)
    selected_placeables = []
    selected_placeables.resize(player_count)
    var selected_count = 0
    is_selecting = true

    grid_manager.show_selector_and_grid()
    # clear players from targets
    $MultiCam.clear_targets()
    show_cursors()
    reset_cursor_positions()
    
    print("Starting placeable selection")
    # loop till all players have selected
    while selected_count < player_count:
        var return_vals = yield(grid_manager, "placeable_selected")
        var placeable = return_vals[0]
        var player = return_vals[1]
        var player_idx = main.players.find(player)

        # continue/skip if player already has already selected to prevent double selection
        if selected_placeables[player_idx] != null:
            continue

        hide_cursor(player_idx)

        selected_placeables[player_idx] = placeable
        placeable.hide()
        selected_count += 1

    grid_manager.hide_selector()
    print("Placeable selection finished")
    
    is_selecting = false
    is_placing = true

    show_cursors()
    
    var placed_count = 0
    print("Starting placeable placement")
    for placeable in selected_placeables:
        placeable.show()

    # loop till all players have placed
    while placed_count < player_count:
        var return_vals = yield(grid_manager, "placeable_placed")
        var _placeable = return_vals[0]
        var player = return_vals[1]
        var player_idx = main.players.find(player)
        hide_cursor(player_idx)

        selected_placeables[player_idx] = null
        placed_count += 1

    print("Placeable placement finished")

    grid_manager.hide_grid()

    is_placing = false
    # clear cursors from targets
    $MultiCam.clear_targets()
    hide_cursors()

func reset_cursor_positions():
    for cursor in main.cursors:
        var pos = grid_manager.position
        pos.x += 700
        pos.y += 700
        
        cursor.set_position(pos)

func show_cursors():
    for cursor in main.cursors:
        cursor.show()
        $MultiCam.add_target(cursor)

func hide_cursors():
    for cursor in main.cursors:
        cursor.hide()

func hide_cursor(player_idx: int):
    var cursor = main.cursors[player_idx]
    cursor.hide()
    $MultiCam.targets.erase(cursor)

func go_to_score_screen():
    print(finish.player_count)
    score_screen.show_score(finish.player_count)

func add_player_to_world(player):
    add_child(player)
    spawn_player(player)
    
    $MultiCam.add_target(player)   

func _ready():
    $MapKillBounds/DownBounds.disabled = true
    connect_events()
    init_grid()
    grid_manager.hide_selector_and_grid()
    score_screen.hide_score()

    for player in main.players:
        player.is_movement_locked = true

    next_round()

func connect_events():
    var _status
    _status = EventHandler.connect("player_killed", self, "_on_player_killed")
    assert(!_status)
    _status = EventHandler.connect("player_reached_finish", self, "_on_player_reached_finish")
    assert(!_status)

# based on the size of the grid_rect
func init_grid():
    grid_manager.grid.size = grid_manager.grid_rect.rect_size / 64
    grid_manager.grid.clear()

    add_map_occupied_tiles_to_grid($Terrain)
    add_map_occupied_tiles_to_grid($Start)
    add_map_occupied_tiles_to_grid($Finish)

func add_map_occupied_tiles_to_grid(tile_map: TileMap):
    var tile_indexes = tile_map.get_used_cells()

    for tile_idx in tile_indexes:
        var tile_local_pos = tile_map.map_to_world(tile_idx)
        var tile_global_pos = tile_map.to_global(tile_local_pos)
        var grid_local_pos = grid_manager.to_local(tile_global_pos)
        var grid_idx = grid_manager.world_to_map(grid_local_pos)
        grid_manager.grid.add_non_placeable_location(grid_idx)

func _on_player_killed(player : PlayerController, source : Node2D):
    if not game_finished and not player.DEAD:
        if source is Placeable:
            print("Player %s killed by Player %s's %s." % [player.name, source.player.name, source.name])
        elif source is KillBoundary:
            print("Player %s killed by %s." % [player.name, "KillBoundary"])
        else:
            print("Player %s killed by %s." % [player.name, "UNKNOWN SOURCE({%s})" % source.name])
        player.death()
        var direction = source.global_position.direction_to(player.global_position)
        # direction.x = -direction.x
        print(direction)
        player.myjump(direction)
        if all_players_finished():
            go_to_score_screen()

func _on_player_reached_finish(player: PlayerController):
    if not game_finished:
        player.is_movement_locked = true
        player.GOAL = true
        if first_player:
            first_player = false
            player.FRST = true
        if all_players_finished():
            go_to_score_screen()

func all_players_finished():
    var finished = true
    for p in main.players:
        finished = finished and (p.DEAD or p.GOAL)
    return finished

func spawn_player(player: PlayerController):
    if len(used_spawns) >= 4:
        return

    var start = $Start
    var spawn_points = $Start/SpawnPoints.get_children()
    
    var spawn_index = 0
    while used_spawns.has(spawn_index):
        spawn_index = randi() % spawn_points.size()
    
    used_spawns.append(spawn_index)
    
    if spawn_points != null and spawn_points.size() > 0:
        var spawn_point = spawn_points[spawn_index] 
        player.position = start.position + spawn_point.position + Vector2.UP * player.get_collider_height()
        player.rotation = spawn_point.rotation
    else:
        printerr("No spawn points found!")
