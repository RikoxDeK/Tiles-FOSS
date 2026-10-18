extends Node2D

enum Screen { LIBRARY, PREPARE, GAME, RESULTS }
const LANES := 4
const NORMAL_HEIGHT := 455.0
const BASE_SPEED := 760.0
const SETTINGS_PATH := "user://settings.cfg"
const SPEED_MIN := 0.5
const SPEED_MAX := 3.0
const SPEED_STEP := 0.1
const HIT_Y := 1580.0
const OsuImporter = preload("res://scripts/osu_importer.gd")
const START_TIME := -100.0
const LIST_TOP := 320.0
const CARD_H := 190.0
const CARD_GAP := 24.0
const DEMO_ENTRY := {"demo": true, "title": "Tiles FOSS Demo", "artist": "Mapa de prueba", "version": "Normal", "badge": "DEMO"}

var screen := Screen.LIBRARY
var viewport_size := Vector2(1080, 1920)
var notes: Array = []
var active_inputs: Dictionary = {}
var effects: Array = []
var song_time := 0.0
var started := false
var paused := false
var finished := false
var score := 0
var combo := 0
var max_combo := 0
var hits := 0
var misses := 0
var last_judgement := ""
var judgement_time := 0.0

# Canción actual
var chart: Array = []
var current_song: Dictionary = {}
var song_stats := {"notes": 0, "holds": 0, "duration": 0.0, "dropped": 0, "total": 0}
var chart_end := 12.4
var lead_in := 0.0          # segundos de cuenta atrás antes de que suene el audio
var use_lead_in := false    # true en mapas importados: la primera nota entra desde arriba
var first_note_time := 0.0

# Velocidad de caída (px/s = BASE_SPEED * multiplicador)
var speed := BASE_SPEED
var ahead := HIT_Y / BASE_SPEED + 0.15   # segundos de notas visibles por delante
var speed_auto := true      # true: usa el multiplicador sugerido para el mapa
var speed_mult := 1.0       # multiplicador manual (se guarda en disco)
var auto_mult := 1.0        # multiplicador sugerido para la canción elegida
var first_idx := 0          # primera nota que aún no se resolvió (notas ordenadas por tiempo)

# Audio
var player: AudioStreamPlayer
var audio_stream: AudioStream = null
var audio_started := false
var audio_offset := 0.0     # calibración manual en segundos (futuro: pantalla de calibración)

# Biblioteca
var groups: Array = []          # una entrada por canción, con todas sus dificultades
var view_groups: Array = []     # groups filtrados por la búsqueda
var open_group: Dictionary = {} # canción cuyo selector de dificultad está abierto
var search_open := false
var search_query := ""
var search_edit: LineEdit
var file_dialog: FileDialog
var scroll_y := 0.0
var press_id := -999
var press_pos := Vector2.ZERO
var dragged := false
var status_text := ""
var status_time := 0.0
var status_error := false

var demo_chart: Array = [
	{"time":0.00,"lane":0,"type":"start"},
	{"time":0.72,"lane":2,"type":"tap"}, {"time":1.22,"lane":1,"type":"tap"},
	{"time":1.72,"lane":3,"type":"tap"}, {"time":2.16,"lane":0,"type":"tap"},
	{"time":2.62,"lane":2,"type":"tap"}, {"time":3.08,"lane":1,"type":"tap"},
	{"time":3.54,"lane":3,"type":"tap"}, {"time":4.02,"lane":0,"type":"hold","duration":1.65},
	{"time":4.55,"lane":2,"type":"tap"}, {"time":5.05,"lane":3,"type":"tap"},
	{"time":5.72,"lane":1,"type":"tap"}, {"time":6.18,"lane":2,"type":"tap"},
	{"time":6.64,"lane":0,"type":"tap"}, {"time":7.08,"lane":3,"type":"hold","duration":1.35},
	{"time":7.55,"lane":1,"type":"tap"}, {"time":8.08,"lane":2,"type":"tap"},
	{"time":8.55,"lane":0,"type":"tap"}, {"time":9.03,"lane":1,"type":"tap"},
	{"time":9.50,"lane":3,"type":"tap"}, {"time":9.96,"lane":2,"type":"tap"},
	{"time":10.42,"lane":0,"type":"tap"}, {"time":10.88,"lane":1,"type":"tap"},
	{"time":11.34,"lane":3,"type":"tap"}
]

func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	player = AudioStreamPlayer.new()
	add_child(player)
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.osz ; Beatmaps de osu!"])
	file_dialog.file_selected.connect(_import_osz)
	add_child(file_dialog)
	get_window().files_dropped.connect(_on_files_dropped)
	_setup_search()
	_load_settings()
	_refresh_library()
	_resize()

func _resize() -> void:
	viewport_size = get_viewport_rect().size
	if search_edit != null:
		search_edit.position = Vector2(55, 140)
		search_edit.size = Vector2(viewport_size.x - 375.0, 105)
	queue_redraw()

func _process(delta: float) -> void:
	if screen == Screen.GAME and started and not paused and not finished:
		song_time += delta
		_sync_audio()
		_update_notes()
	if search_edit != null:
		search_edit.visible = screen == Screen.LIBRARY and search_open and open_group.is_empty()
	if judgement_time > 0.0:
		judgement_time -= delta
	if status_time > 0.0:
		status_time -= delta
	for effect in effects:
		effect.time -= delta
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].time <= 0.0:
			effects.remove_at(i)
	queue_redraw()

func _sync_audio() -> void:
	if audio_stream == null:
		return
	if not audio_started:
		if song_time >= 0.0:
			audio_started = true
			player.play()
		return
	if not player.playing:
		return
	# El reloj avanza con delta y se corrige suavemente contra la posición real del audio.
	var audio_time := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() + audio_offset
	var error := audio_time - song_time
	if abs(error) > 0.08:
		song_time = audio_time
	else:
		song_time += error * 0.1

func _update_notes() -> void:
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > ahead:
			break
		if note.done:
			continue
		if note.type == "hold" and note.holding:
			var held: bool = note.input_id in active_inputs and active_inputs[note.input_id] == note.lane
			if not held and song_time < note.time + note.duration - 0.12:
				note.done = true
				note.holding = false
				_miss(note.lane, HIT_Y)
			elif song_time >= note.time + note.duration:
				note.done = true
				note.holding = false
				_hit(note.lane, "PERFECT", 180, HIT_Y)
		elif note.type != "start" and song_time > note.time + 0.28:
			var miss_position: float = HIT_Y + (song_time - note.time) * speed
			note.done = true
			_miss(note.lane, miss_position)
	while first_idx < notes.size() and notes[first_idx].done:
		first_idx += 1
	if song_time > chart_end and not finished:
		finished = true
		await get_tree().create_timer(0.7).timeout
		if screen == Screen.GAME:
			_stop_audio()
			screen = Screen.RESULTS

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_pointer(event.position, event.pressed, event.index)
	elif event is InputEventScreenDrag:
		_library_drag(event.position, event.relative, event.index)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_library_drag(event.position, event.relative, -1)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if screen == Screen.LIBRARY:
			scroll_y += -120.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0
			_clamp_scroll()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(event.position, event.pressed, -1)
	elif event is InputEventKey and screen == Screen.GAME:
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_set_paused(not paused)
			return
		var lane: int = _key_lane(event)
		if lane >= 0:
			var input_id: int = -100 - lane
			if event.pressed and not event.echo:
				active_inputs[input_id] = lane
				_try_hit(lane, input_id)
			elif not event.pressed:
				active_inputs.erase(input_id)

func _key_lane(event: InputEventKey) -> int:
	var key: Key = event.physical_keycode
	if key == KEY_D: return 0
	if key == KEY_F: return 1
	if key == KEY_J: return 2
	if key == KEY_K: return 3
	return -1

func _pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if screen == Screen.LIBRARY:
		_library_pointer(pos, pressed, input_id)
		return
	if not pressed:
		active_inputs.erase(input_id)
		return
	if screen == Screen.PREPARE:
		if Rect2(100, 1360, viewport_size.x - 200, 145).has_point(pos): _start_game()
		elif Rect2(35, 45, 180, 95).has_point(pos): screen = Screen.LIBRARY
		elif Rect2(100, 1130, 190, 120).has_point(pos): _adjust_speed(-SPEED_STEP)
		elif Rect2(viewport_size.x - 290, 1130, 190, 120).has_point(pos): _adjust_speed(SPEED_STEP)
		elif Rect2(310, 1130, viewport_size.x - 620, 120).has_point(pos): speed_auto = not speed_auto; _save_settings()
	elif screen == Screen.GAME:
		if Rect2(viewport_size.x - 145, 35, 110, 100).has_point(pos):
			_set_paused(not paused)
			return
		if paused:
			if Rect2(170, 760, viewport_size.x - 340, 135).has_point(pos): _set_paused(false)
			elif Rect2(170, 930, viewport_size.x - 340, 135).has_point(pos): _go_library()
			return
		var lane: int = clampi(int(pos.x / (viewport_size.x / LANES)), 0, LANES - 1)
		active_inputs[input_id] = lane
		_try_hit(lane, input_id)
	elif screen == Screen.RESULTS:
		if Rect2(110, 1400, viewport_size.x - 220, 135).has_point(pos): _start_game()
		elif Rect2(110, 1570, viewport_size.x - 220, 120).has_point(pos): open_group = {}; screen = Screen.LIBRARY

func _start_game() -> void:
	_stop_audio()
	screen = Screen.GAME
	speed = BASE_SPEED * _effective_mult()
	ahead = HIT_Y / speed + 0.15
	# Que la primera nota entre desde arriba justo al empezar.
	lead_in = maxf(0.0, HIT_Y / speed + 0.05 - first_note_time) if use_lead_in else 0.0
	notes.clear()
	for data in chart:
		var note: Dictionary = data.duplicate(true)
		note.done = false
		note.holding = false
		note.input_id = -999
		note.height = NORMAL_HEIGHT
		notes.append(note)
	# Un tap no debe solaparse con la siguiente nota de su carril.
	var next_time := {}
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		if n.type == "start":
			continue
		if n.type == "tap" and next_time.has(n.lane):
			n.height = clampf((next_time[n.lane] - n.time) * speed - 6.0, 50.0, NORMAL_HEIGHT)
		next_time[n.lane] = n.time
	first_idx = 0
	player.stream = audio_stream
	active_inputs.clear(); effects.clear()
	song_time = -lead_in; started = false; paused = false; finished = false
	score = 0; combo = 0; max_combo = 0; hits = 0; misses = 0

func _try_hit(lane: int, input_id: int) -> void:
	if not started:
		for note in notes:
			if note.type == "start" and note.lane == lane and not note.done:
				note.done = true; started = true; song_time = -lead_in; audio_started = false
				_hit(lane, "COMENZAR", 0, HIT_Y)
				return
		_effect(lane, HIT_Y, Color(1.0, 0.15, 0.18, 0.84))
		return
	var best: Dictionary = {}
	var best_diff := 999.0
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > 0.3: break
		if note.done or note.type == "start" or note.lane != lane: continue
		var diff: float = abs(song_time - note.time)
		if diff < best_diff:
			best_diff = diff; best = note
	if best.is_empty() or best_diff > 0.28:
		combo = 0; last_judgement = "VACÍO"; judgement_time = 0.35
		_effect(lane, HIT_Y, Color(1.0, 0.15, 0.18, 0.84))
		return
	if best.type == "hold":
		best.holding = true; best.input_id = input_id
		last_judgement = "MANTÉN"; judgement_time = 0.4
		_effect(lane, HIT_Y, Color(1, 1, 1, 0.82))
	else:
		best.done = true
		var judgement := "PERFECT" if best_diff <= 0.09 else ("GREAT" if best_diff <= 0.18 else "GOOD")
		var points := 100 if judgement == "PERFECT" else (75 if judgement == "GREAT" else 50)
		_hit(lane, judgement, points, HIT_Y)

func _hit(lane: int, text: String, points: int, effect_y: float) -> void:
	hits += 1; combo += 1; max_combo = max(max_combo, combo); score += points + min(combo, 50)
	last_judgement = text; judgement_time = 0.48
	_effect(lane, effect_y, Color(1, 1, 1, 0.82))

func _miss(lane: int, effect_y: float) -> void:
	misses += 1; combo = 0; last_judgement = "MISS"; judgement_time = 0.55
	_effect(lane, effect_y, Color(1.0, 0.15, 0.18, 0.84))

func _effect(lane: int, effect_y: float, color: Color) -> void:
	effects.append({"lane":lane, "y":effect_y, "color":color, "time":0.20, "duration":0.20})

# --- Biblioteca e importación -------------------------------------------

func _refresh_library() -> void:
	var entries: Array = [DEMO_ENTRY]
	entries.append_array(OsuImporter.scan_library())
	groups = _group_entries(entries)
	open_group = {}
	_apply_filter()

## Agrupa las dificultades de un mismo .osz (misma carpeta) en una sola canción.
func _group_entries(entries: Array) -> Array:
	var out: Array = []
	var by_id := {}
	for e in entries:
		var id: String = e.get("set_id", "demo")
		if not by_id.has(id):
			var g := {"id": id, "title": e.title, "artist": e.artist, "creator": e.get("creator", ""), "entries": []}
			by_id[id] = g
			out.append(g)
		by_id[id].entries.append(e)
	# Dentro de cada canción: por modo y de menor a mayor (el tamaño del .osu
	# sirve de aproximación a la dificultad: más notas, archivo más grande).
	for g in out:
		g.entries.sort_custom(func(a, b):
			if a.badge != b.badge:
				return a.badge.naturalnocasecmp_to(b.badge) < 0
			return int(a.get("size", 0)) < int(b.get("size", 0)))
	return out

func _apply_filter() -> void:
	var words := search_query.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		view_groups = groups
	else:
		view_groups = groups.filter(func(g): return _group_matches(g, words))
	scroll_y = 0.0
	_clamp_scroll()

func _group_matches(g: Dictionary, words: PackedStringArray) -> bool:
	var hay := "%s %s %s" % [g.title, g.artist, g.creator]
	for e in g.entries:
		hay += " " + String(e.version) + " " + String(e.badge)
	hay = hay.to_lower()
	for w in words:
		if not hay.contains(w):
			return false
	return true

func _setup_search() -> void:
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Canción, artista o dificultad"
	search_edit.clear_button_enabled = true
	search_edit.visible = false
	search_edit.add_theme_font_size_override("font_size", 36)
	search_edit.add_theme_color_override("font_color", Color(0.12, 0.22, 0.31))
	search_edit.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
	search_edit.add_theme_color_override("caret_color", Color(0.02, 0.62, 0.86))
	search_edit.add_theme_color_override("clear_button_color", Color(0.4, 0.5, 0.6))
	search_edit.add_theme_color_override("clear_button_color_pressed", Color(0.02, 0.62, 0.86))
	for style_name in ["normal", "focus", "read_only"]:
		var box := _box(Color(0.97, 0.98, 1), 24)
		box.content_margin_left = 28.0
		box.content_margin_right = 20.0
		search_edit.add_theme_stylebox_override(style_name, box)
	search_edit.text_changed.connect(_on_search_changed)
	search_edit.text_submitted.connect(func(_t): search_edit.release_focus())
	add_child(search_edit)

func _on_search_changed(text: String) -> void:
	search_query = text
	_apply_filter()

func _open_search() -> void:
	search_open = true
	search_edit.visible = true
	search_edit.grab_focus.call_deferred()

func _close_search() -> void:
	search_open = false
	search_edit.release_focus()
	search_edit.text = ""
	search_query = ""
	_apply_filter()

## Posición del panel de dificultades y de cada fila (para dibujar y para tocar).
func _picker_layout() -> Dictionary:
	var n: int = open_group.entries.size()
	var head := 170.0
	var max_h := viewport_size.y - 240.0
	var row_h := clampf((max_h - head - 30.0) / n - 14.0, 70.0, 130.0)
	var h := head + n * (row_h + 14.0) + 16.0
	var panel := Rect2(55, (viewport_size.y - h) / 2.0, viewport_size.x - 110.0, h)
	var rows: Array = []
	for i in n:
		rows.append(Rect2(panel.position.x + 28, panel.position.y + head + i * (row_h + 14.0), panel.size.x - 56, row_h))
	return {"panel": panel, "rows": rows}

func _badge_color(e: Dictionary) -> Color:
	if e.demo:
		return Color(0.18, 0.66, 0.92)
	return Color(0.95, 0.55, 0.2) if e.badge == "STD" else Color(0.93, 0.36, 0.62)

func _import_osz(path: String) -> void:
	var result: Dictionary = OsuImporter.import_osz(path)
	if result.ok:
		_refresh_library()
		_show_status("Importado: %s (%d dificultades)" % [result.title, result.count], false)
	else:
		_show_status(result.error, true)

func _on_files_dropped(files: PackedStringArray) -> void:
	if screen != Screen.LIBRARY:
		return
	for f in files:
		if f.to_lower().ends_with(".osz"):
			_import_osz(f)
		else:
			_show_status("Solo se admiten archivos .osz", true)

func _show_status(text: String, is_error: bool) -> void:
	status_text = text; status_error = is_error; status_time = 6.0

func _library_pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if pressed:
		press_id = input_id; press_pos = pos; dragged = false
	elif input_id == press_id:
		press_id = -999
		if not dragged:
			_library_tap(pos)

func _library_drag(pos: Vector2, relative: Vector2, input_id: int) -> void:
	if screen != Screen.LIBRARY or input_id != press_id or not open_group.is_empty():
		return
	if not dragged and pos.distance_to(press_pos) > 24.0:
		dragged = true
	if dragged:
		scroll_y -= relative.y
		_clamp_scroll()

func _clamp_scroll() -> void:
	var content := view_groups.size() * (CARD_H + CARD_GAP)
	scroll_y = clampf(scroll_y, 0.0, maxf(0.0, content - (viewport_size.y - LIST_TOP) + 40.0))

func _library_tap(pos: Vector2) -> void:
	# Selector de dificultad abierto: solo responde él.
	if not open_group.is_empty():
		var layout := _picker_layout()
		var panel: Rect2 = layout.panel
		if not panel.has_point(pos):
			open_group = {}
			return
		for i in layout.rows.size():
			var row: Rect2 = layout.rows[i]
			if row.has_point(pos):
				_select_song(open_group.entries[i])
				return
		return
	search_edit.release_focus()
	if search_open:
		if Rect2(viewport_size.x - 300, 150, 245, 95).has_point(pos):
			_close_search()
			return
	else:
		if Rect2(viewport_size.x - 670, 150, 245, 95).has_point(pos):
			_open_search()
			return
		if Rect2(viewport_size.x - 405, 150, 350, 95).has_point(pos):
			file_dialog.popup_centered_ratio(0.85)
			return
	if pos.y < LIST_TOP - 22.0 or pos.x < 55.0 or pos.x > viewport_size.x - 55.0:
		return
	var offset := pos.y - LIST_TOP + scroll_y
	var idx := int(offset / (CARD_H + CARD_GAP))
	if offset >= 0.0 and fmod(offset, CARD_H + CARD_GAP) <= CARD_H and idx < view_groups.size():
		var g: Dictionary = view_groups[idx]
		if g.entries.size() == 1:
			_select_song(g.entries[0])
		else:
			open_group = g

func _select_song(entry: Dictionary) -> void:
	var new_chart: Array = []
	var stream: AudioStream = null
	var new_lead := false
	var new_first := 0.0
	var new_auto := 1.0
	var new_end := 12.4
	var dropped := 0
	var total := 0
	if entry.demo:
		new_chart = demo_chart
	else:
		var parsed: Dictionary = OsuImporter.parse_osu(FileAccess.get_file_as_string(entry.osu_path))
		if not parsed.ok:
			_show_status(parsed.error, true)
			return
		var playable: Array = OsuImporter.build_chart(parsed)
		if playable.is_empty():
			_show_status("No quedaron notas jugables en este mapa", true)
			return
		new_chart = [{"time": START_TIME, "lane": 0, "type": "start"}]
		new_chart.append_array(playable)
		new_lead = true
		new_first = float(playable[0].time)
		new_auto = OsuImporter.suggest_speed(playable)
		total = parsed.objects.size()
		dropped = total - playable.size()
		var last_end := 0.0
		for n in playable:
			last_end = maxf(last_end, float(n.time) + float(n.get("duration", 0.0)))
		new_end = last_end + 1.06
		stream = OsuImporter.load_audio(entry.audio_path)
	var note_count := 0
	var hold_count := 0
	for n in new_chart:
		if n.type == "start": continue
		note_count += 1
		if n.type == "hold": hold_count += 1
	var duration := new_end - 1.06
	if stream != null and stream.get_length() > 0.0:
		duration = stream.get_length()
	chart = new_chart; chart_end = new_end; use_lead_in = new_lead; first_note_time = new_first; auto_mult = new_auto
	audio_stream = stream; current_song = entry
	song_stats = {"notes": note_count, "holds": hold_count, "duration": duration, "dropped": dropped, "total": total}
	screen = Screen.PREPARE

# --- Velocidad y ajustes -------------------------------------------------

func _effective_mult() -> float:
	return auto_mult if speed_auto else speed_mult

func _adjust_speed(delta: float) -> void:
	speed_mult = snappedf(clampf(_effective_mult() + delta, SPEED_MIN, SPEED_MAX), SPEED_STEP)
	speed_auto = false
	_save_settings()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	speed_auto = cfg.get_value("speed", "auto", true)
	speed_mult = clampf(float(cfg.get_value("speed", "mult", 1.0)), SPEED_MIN, SPEED_MAX)

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("speed", "auto", speed_auto)
	cfg.set_value("speed", "mult", speed_mult)
	cfg.save(SETTINGS_PATH)

func _text_centered(value: String, center_x: float, y: float, size: int, color: Color) -> void:
	var width := _font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(center_x - width / 2, y), size, color)

# --- Pausa / audio -------------------------------------------------------

func _set_paused(value: bool) -> void:
	paused = value
	player.stream_paused = value

func _stop_audio() -> void:
	player.stop()
	player.stream_paused = false
	audio_started = false

func _go_library() -> void:
	_stop_audio()
	open_group = {}
	screen = Screen.LIBRARY

func _format_time(seconds: float) -> String:
	var total := int(round(seconds))
	return "%d:%02d" % [total / 60, total % 60]

func _fit(value: String, max_width: float, size: int) -> String:
	var font := _font()
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_width:
		return value
	while value.length() > 1 and font.get_string_size(value + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_width:
		value = value.substr(0, value.length() - 1)
	return value + "..."

func _draw() -> void:
	if screen == Screen.LIBRARY: _draw_library()
	elif screen == Screen.PREPARE: _draw_prepare()
	elif screen == Screen.GAME: _draw_game()
	else: _draw_results()

func _draw_game() -> void:
	var lane_w := viewport_size.x / LANES
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.74, 0.88, 0.98))
	for lane in LANES:
		draw_rect(Rect2(lane * lane_w, 0, lane_w, viewport_size.y), Color(0.9,0.96,1,0.20))
		draw_line(Vector2(lane * lane_w,0), Vector2(lane * lane_w,viewport_size.y), Color.WHITE, 3)
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > ahead: break
		if note.done or (note.type == "start" and started): continue
		var bottom: float = viewport_size.y if note.type == "start" and not started else HIT_Y - (note.time - song_time) * speed
		var height: float = note.height
		if note.type == "hold":
			if note.holding:
				var remaining: float = max(0.0, note.time + note.duration - song_time)
				height = max(90.0, remaining * speed)
				bottom = HIT_Y
			else:
				height = maxf(120.0, note.duration * speed)
		var rect := Rect2(note.lane * lane_w + 2, bottom - height, lane_w - 4, height)
		if note.type == "hold":
			# Misma silueta cayendo y sosteniendo: solo cambia la intensidad.
			draw_rect(rect, Color(0.01, 0.035, 0.06) if not note.holding else Color(0.0, 0.07, 0.11))
			_draw_hold_marks(rect, note.holding)
		else:
			draw_rect(rect, Color(0.01,0.01,0.015))
		if note.type == "start": _text("Comenzar", Vector2(rect.position.x+18,rect.get_center().y+12), 35, Color.WHITE)
	for effect in effects:
		var progress: float = 1.0 - float(effect.time) / float(effect.duration)
		var color: Color = effect.color; color.a *= 1.0 - progress
		var center := Vector2((float(effect.lane)+0.5)*lane_w, float(effect.y))
		var half := Vector2(lane_w*(0.20+progress*0.24), 28.0+progress*38.0)
		draw_rect(Rect2(center-half, half*2.0), color, false, 7.0)
	if judgement_time > 0:
		var color := Color(1,0.2,0.22) if last_judgement in ["MISS","VACÍO"] else Color(0.08,0.15,0.22)
		_text(last_judgement, Vector2(viewport_size.x/2-110,340), 48, color)
	_text(str(hits), Vector2(viewport_size.x/2-25,155), 72, Color(1,0.22,0.28))
	_text("Combo %d" % combo, Vector2(35,95), 30, Color(0.12,0.22,0.32))
	_button(Rect2(viewport_size.x-145,35,110,100), "II", Color(0.06,0.12,0.2,0.72))
	if paused:
		draw_rect(Rect2(Vector2.ZERO,viewport_size), Color(0,0,0,0.74))
		_text("PAUSA", Vector2(viewport_size.x/2-110,600), 62, Color.WHITE)
		_button(Rect2(170,760,viewport_size.x-340,135), "CONTINUAR", Color(0.02,0.68,0.88))
		_button(Rect2(170,930,viewport_size.x-340,135), "SALIR", Color(0.22,0.28,0.38))

## Línea + círculo de las notas sostenidas. Inactiva (cayendo): cian tenue.
## Activa (sostenida): cian brillante y círculo relleno.
func _draw_hold_marks(rect: Rect2, active: bool) -> void:
	var cx := rect.get_center().x
	var head := Vector2(cx, rect.end.y - 55.0)
	var color := Color(0.0, 0.95, 1.0, 1.0 if active else 0.5)
	var width := 7.0 if active else 5.0
	if head.y - 25.0 > rect.position.y + 25.0:
		draw_line(Vector2(cx, rect.position.y + 25.0), Vector2(cx, head.y - 15.0), color, width)
	if active:
		draw_circle(head, 30.0, Color(0.0, 0.95, 1.0, 0.22))
	draw_arc(head, 30.0, 0, TAU, 40, color, width)

func _draw_library() -> void:
	var bg := Color(0.025, 0.05, 0.1)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), bg)
	var x := 55.0
	var w := viewport_size.x - 110.0
	for i in view_groups.size():
		var g: Dictionary = view_groups[i]
		var first: Dictionary = g.entries[0]
		var count: int = g.entries.size()
		var y := LIST_TOP + i * (CARD_H + CARD_GAP) - scroll_y
		if y + CARD_H < 0.0 or y > viewport_size.y: continue
		_panel(Rect2(x, y, w, CARD_H), Color(0.97, 0.98, 1), 28)
		draw_rect(Rect2(x, y, 190, CARD_H), _badge_color(first))
		if count > 1:
			_text_centered(first.badge, x + 95, y + CARD_H / 2 - 2, 44, Color.WHITE)
			_text_centered("%d dif." % count, x + 95, y + CARD_H / 2 + 44, 28, Color(1, 1, 1, 0.9))
		else:
			_text_centered(first.badge, x + 95, y + CARD_H / 2 + 15, 44, Color.WHITE)
		var text_w := w - 190 - 60
		_text(_fit(g.title, text_w, 38), Vector2(x + 215, y + 82), 38, Color(0.12, 0.22, 0.31))
		var sub: String = ("%s · %d dificultades" % [g.artist, count]) if count > 1 else ("%s · %s" % [g.artist, first.version])
		_text(_fit(sub, text_w, 27), Vector2(x + 215, y + 132), 27, Color(0.42, 0.52, 0.62))
	if view_groups.is_empty():
		_text(_fit("Sin resultados para \"%s\"" % search_query, w, 30), Vector2(x, LIST_TOP + 70), 30, Color(0.62, 0.75, 0.88))
	elif groups.size() == 1 and not search_open:
		var hint_y := LIST_TOP + CARD_H + CARD_GAP + 70.0 - scroll_y
		_text("Importa un mapa de osu! (.osz) con el botón de arriba", Vector2(x, hint_y), 28, Color(0.62, 0.75, 0.88))
		_text("o arrastra el archivo a la ventana (PC).", Vector2(x, hint_y + 44), 28, Color(0.62, 0.75, 0.88))
	# La cabecera tapa las tarjetas que suben por debajo.
	draw_rect(Rect2(0, 0, viewport_size.x, LIST_TOP - 22), bg)
	_text("TILES FOSS", Vector2(55, 105), 58, Color.WHITE)
	if search_open:
		_button(Rect2(viewport_size.x - 300, 150, 245, 95), "Cerrar", Color(0.17, 0.25, 0.37))
	else:
		_text("Canciones", Vector2(55, 205), 42, Color(0.82, 0.91, 1))
		_button(Rect2(viewport_size.x - 670, 150, 245, 95), "Buscar", Color(0.14, 0.22, 0.34))
		_button(Rect2(viewport_size.x - 405, 150, 350, 95), "Importar .osz", Color(0.04, 0.65, 0.88))
	if not open_group.is_empty():
		_draw_difficulty_picker()
	if status_time > 0.0:
		_text(_fit(status_text, viewport_size.x - 110, 26), Vector2(55, 272), 26, Color(1, 0.45, 0.45) if status_error else Color(0.5, 0.95, 0.75))

func _draw_difficulty_picker() -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.62))
	var layout := _picker_layout()
	var panel: Rect2 = layout.panel
	_panel(panel, Color(0.97, 0.98, 1), 34)
	var inner_w := panel.size.x - 80.0
	_text(_fit(open_group.title, inner_w, 44), Vector2(panel.position.x + 40, panel.position.y + 76), 44, Color(0.12, 0.22, 0.31))
	var sub: String = open_group.artist
	if not String(open_group.creator).is_empty():
		sub += " · mapa de %s" % open_group.creator
	_text(_fit(sub, inner_w, 27), Vector2(panel.position.x + 40, panel.position.y + 125), 27, Color(0.42, 0.52, 0.62))
	for i in layout.rows.size():
		var r: Rect2 = layout.rows[i]
		var e: Dictionary = open_group.entries[i]
		_panel(r, Color(0.88, 0.94, 1), 24)
		_panel(Rect2(r.position.x, r.position.y, 130, r.size.y), _badge_color(e), 24)
		_text_centered(e.badge, r.position.x + 65, r.get_center().y + 12, 34, Color.WHITE)
		_text(_fit(e.version, r.size.x - 180, 34), Vector2(r.position.x + 155, r.get_center().y + 12), 34, Color(0.12, 0.22, 0.31))

func _draw_prepare() -> void:
	_background(); _button(Rect2(35,45,180,95),"< Volver",Color(0.14,0.22,0.34))
	var text_w := viewport_size.x - 160
	_text(_fit(current_song.title, text_w, 58), Vector2(80,370), 58, Color.WHITE)
	_text(_fit("%s · %s" % [current_song.artist, current_song.version], text_w, 32), Vector2(82,445), 32, Color(0.68,0.84,0.96))
	_panel(Rect2(80,580,viewport_size.x-160,440),Color(0.08,0.13,0.22,0.92),34)
	_text("%d notas · %d sostenidas" % [song_stats.notes, song_stats.holds], Vector2(140,690), 38, Color.WHITE)
	_text("%s · %s" % [_format_time(song_stats.duration), "Con audio" if audio_stream != null else "Sin audio"], Vector2(140,770), 38, Color.WHITE if audio_stream != null else Color(1,0.6,0.6))
	if song_stats.dropped > 0:
		_text("Adaptado a %d dedos: se quitaron %d de %d notas" % [OsuImporter.DEFAULT_MAX_FINGERS, song_stats.dropped, song_stats.total], Vector2(140,850), 28, Color(0.62,0.75,0.88))
	_text("PC: D · F · J · K", Vector2(140,970), 28, Color(0.62,0.75,0.88))
	# Velocidad
	var cx := viewport_size.x / 2
	_button(Rect2(100,1130,190,120),"-",Color(0.14,0.22,0.34))
	_button(Rect2(viewport_size.x-290,1130,190,120),"+",Color(0.14,0.22,0.34))
	_text_centered("Velocidad · AUTO" if speed_auto else "Velocidad · MANUAL (toca: auto)", cx, 1172, 28, Color(0.62,0.75,0.88))
	_text_centered("x%.1f" % _effective_mult(), cx, 1232, 56, Color(0.3,0.9,1.0) if speed_auto else Color.WHITE)
	_button(Rect2(100,1360,viewport_size.x-200,145),"JUGAR",Color(0.02,0.68,0.88))

func _draw_results() -> void:
	_background(); _text("RESULTADOS",Vector2(310,230),58,Color.WHITE)
	_panel(Rect2(90,350,viewport_size.x-180,760),Color(0.96,0.98,1),38)
	_text("Puntuación",Vector2(170,590),29,Color(0.42,0.52,0.62)); _text(str(score),Vector2(170,680),68,Color(0.02,0.62,0.86))
	_text("Aciertos: %d"%hits,Vector2(170,820),34,Color(0.12,0.22,0.32)); _text("Fallos: %d"%misses,Vector2(170,890),34,Color(0.12,0.22,0.32))
	_text("Combo máximo: %d"%max_combo,Vector2(170,960),34,Color(0.12,0.22,0.32))
	_button(Rect2(110,1400,viewport_size.x-220,135),"REPETIR",Color(0.02,0.68,0.88)); _button(Rect2(110,1570,viewport_size.x-220,120),"CANCIONES",Color(0.17,0.25,0.37))

func _background() -> void:
	draw_rect(Rect2(Vector2.ZERO,viewport_size),Color(0.025,0.05,0.1))
	for i in range(10): draw_circle(Vector2(viewport_size.x*0.75,viewport_size.y*0.22),700-i*50,Color(0,0.58,0.95,0.025))

func _button(rect: Rect2, label: String, color: Color) -> void:
	_panel(rect,color,24); var width := _font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,34).x
	_text(label,Vector2(rect.get_center().x-width/2,rect.get_center().y+12),34,Color.WHITE)

func _panel(rect: Rect2, color: Color, radius: float) -> void: draw_style_box(_box(color,radius),rect)
func _box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color=color
	box.corner_radius_top_left=int(radius); box.corner_radius_top_right=int(radius); box.corner_radius_bottom_left=int(radius); box.corner_radius_bottom_right=int(radius)
	return box
func _text(value: String, pos: Vector2, size: int, color: Color) -> void: draw_string(_font(),pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func _font() -> Font: return ThemeDB.fallback_font
