extends Node2D

enum Screen { LIBRARY, PREPARE, GAME, RESULTS, SETTINGS }
const LANES := 4
const NORMAL_HEIGHT := 455.0
const BASE_SPEED := 760.0
const SETTINGS_PATH := "user://settings.cfg"
const SPEED_MIN := 0.5
const SPEED_MAX := 5.0
const SPEED_STEP := 0.1
const HIT_MARGIN := 340.0   # distancia de la línea de golpeo al borde inferior de la pantalla
const OsuImporter = preload("res://scripts/osu_importer.gd")
const START_TIME := -100.0
const LIST_TOP := 320.0
const RANKS := ["D", "C", "B", "A", "S", "SS"]
const RANK_COLORS := [Color(0.55, 0.6, 0.68), Color(0.35, 0.75, 0.55), Color(0.2, 0.7, 0.95), Color(0.55, 0.5, 1.0), Color(1.0, 0.75, 0.2), Color(1.0, 0.45, 0.75)]
## Cuánto sube la velocidad de la CANCIÓN (audio y ritmo) en cada vuelta del Infinito.
## 0.0 = la canción siempre suena igual (solo caen más rápido las notas), 0.1 = x1.1, x1.2...
## La caída de las notas sigue la escala x1.0, x1.5, x2.0... de siempre: al subir la canción,
## las notas se separan menos, así que esta cifra es la que las "aglomera" más o menos.
const LAP_SONG_STEP := 0.1
const PERFECT_WINDOW := 0.12
const GREAT_WINDOW := 0.20
## Niveles de dificultad de notas: cuánto se filtra al adaptar el mapa a dos dedos.
## "event" = segundos mínimos entre grupos de notas; "lane" = entre notas del mismo carril.
## Siempre se mantiene el límite de dos dedos y las reglas de comodidad.
const DIFFICULTY_LEVELS := [
	{"name": "Relajado", "event": 0.20, "lane": 0.14, "color": Color(0.5, 0.95, 0.75)},
	{"name": "Normal", "event": 0.16, "lane": 0.12, "color": Color(1, 1, 1)},
	{"name": "Intenso", "event": 0.125, "lane": 0.10, "color": Color(1.0, 0.75, 0.4)},
	{"name": "Extremo", "event": 0.10, "lane": 0.085, "color": Color(1.0, 0.45, 0.45)},
	{"name": "Máximo", "event": 0.08, "lane": 0.07, "color": Color(1.0, 0.5, 0.85)},
]
const INBOX_NAME := "Por importar"
const BACKUP_NAME := "Importadas"
const LIVES_MIN := 3
const LIVES_MAX := 10
const RESUME_BACKOFF := 0.10    # al continuar, la canción retoma este tiempo antes de la tecla
const GRACE_AFTER_CONTINUE := 1.0
const HIT_LATE := 0.28      # segundos de margen para tocar una tecla tarde
const NAV_H := 170.0        # alto de la barra inferior (en el centro, donde está más alta)
const NAV_BULGE := 34.0     # cuánto más baja es la barra en los bordes: forma de "panza"
const PROGRESS_FILE := "progreso.cfg"   # récords, listas y favoritas, dentro de la carpeta de canciones
const TAB_HOME := 0
const TAB_MUSIC := 1
const TAB_FILES := 2
const SORT_MODES := ["Título", "Artista", "Recientes", "Dificultades"]
const CARD_H := 190.0
const CARD_GAP := 24.0
const DEMO_ENTRY := {"demo": true, "title": "Tiles FOSS Demo", "artist": "Mapa de prueba", "version": "Normal", "badge": "DEMO"}

var screen := Screen.LIBRARY
var viewport_size := Vector2(1080, 1920)
var ui_off := 0.0        # desplazamiento vertical para centrar los menús (pantallas más altas que 16:9)
var top_inset := 0.0     # margen superior por cámara frontal / muesca, en unidades del viewport
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
var perfects := 0
var greats := 0
var goods := 0
var empties := 0
var run_rank := 0
var run_accuracy := 0.0
var run_record := false
var bests: Dictionary = {}   # clave de mapa -> {"score", "rank", "acc"}
var last_judgement := ""
var judgement_time := 0.0
var judgement_total := 0.5
var lives_mode := false      # modo Vidas (ajuste guardado); false = Casual
var lives_setting := 3       # vidas elegidas para la próxima partida (3..10)
var lives_left := 0
var run_lives := 0           # vidas con las que empezó esta partida (0 = casual)
var life_menu := false       # menú "perdiste una vida"
var life_menu_lock := 0.0    # evita tocar sin querer el menú justo al aparecer
var resume_pending := false  # tras continuar: la siguiente tecla hace de "Continuar"
var resume_idxs: Array = []   # índices de las notas (acorde) que hacen de "Continuar"
var grace_time := 0.0        # tras continuar, un segundo sin perder vidas
var failed := false
var fail_text := ""
var run_mult := 1.0
var diff_level := 1          # índice en DIFFICULTY_LEVELS (1 = Normal)
var current_parsed: Dictionary = {}   # mapa .osu parseado de la canción abierta
var library_dir := ""        # carpeta de canciones elegida ("" = sin configurar)
var syncing := false
var bg_blend := 0.0       # 0 = fondo azul normal, 1 = fondo de las 3 estrellas
var play_rate := 1.0      # velocidad de la canción (audio y reloj): sube con cada vuelta del Infinito
var previewing := false   # escuchando solo el audio en la pantalla de preparar
var perm_asked := false   # ya pedimos el permiso de archivos en esta sesión
var folder_dialog: FileDialog
var infinite_mode := false   # ajuste: modo Infinito (usa las vidas)
var infinite_run := false    # esta partida es infinita
var lap := 1
var lap_factor := 1.0
var award_idx := 0
var stars := 0
var crowns := 0
var banner_text := ""
var banner_kind := ""
var banner_time := 0.0
var lap_banner_text := ""
var lap_banner_time := 0.0
var combo_pop := 0.0
var show_bg := true          # ajuste: mostrar la imagen de fondo del mapa
var bg_vis := 0.30           # ajuste: cuánto se ve la imagen (0.1 - 0.7)
var bg_texture: Texture2D = null
var show_thumbs := true      # ajuste: miniaturas en las canciones de la biblioteca
var fav_only := false        # (sin uso: ahora se usa music_tab)
var tab := TAB_HOME          # pestaña de la barra inferior (0 Inicio, 1 Música, 2 Archivos)
var music_tab := 0           # dentro de Música: 0 Todas, 1 Favoritas, 2 Listas
var open_playlist := -1      # lista abierta (-1 = se ven todas las listas)
var sort_mode := 0           # índice en SORT_MODES
var playlists: Array = []    # [{"name": String, "refs": ["set_id|version", ...]}]
var last_played: Dictionary = {}
var overlay := ""            # ventana abierta: "sort", "addto" o "newlist"
var newlist_then_add := false
var delete_armed := false
var name_edit: LineEdit
var scroll_vel := 0.0        # inercia del desplazamiento (px/s)
var drag_ms := 0
var home_records: Array = []
var home_dirty := true
var home_tex: Texture2D = null   # imagen de la última canción jugada (cabecera de Inicio)
var home_tex_path := ""
var progress_merged := false   # ya se leyó progreso.cfg en esta sesión (evita pisarlo con datos vacíos)
var favorites: Dictionary = {}   # id de canción -> true
var thumb_cache: Dictionary = {} # ruta de imagen -> Texture2D (o null si no se pudo leer)
var thumb_budget := 1            # miniaturas que se pueden decodificar por fotograma

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
var hit_y := 1580.0         # se recalcula en _resize según el alto real de la pantalla
var ahead := 1580.0 / BASE_SPEED + 0.15   # segundos de notas visibles por delante
var speed_auto := false     # true: usa el multiplicador sugerido para el mapa
var speed_mult := 3.0       # multiplicador manual (se guarda en disco)
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
	folder_dialog = FileDialog.new()
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.use_native_dialog = true
	folder_dialog.dir_selected.connect(_set_library_dir)
	add_child(folder_dialog)
	get_window().files_dropped.connect(_on_files_dropped)
	_setup_search()
	_setup_name_edit()
	_load_settings()
	if _merge_progress_file():
		_save_settings()
	_refresh_library()
	_resize()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()

## Botón "atrás" de Android: retrocede una pantalla en vez de cerrar el juego.
func _go_back() -> void:
	if overlay != "":
		_close_overlay()
		return
	match screen:
		Screen.GAME:
			if life_menu or resume_pending or finished:
				return
			_set_paused(not paused)
		Screen.PREPARE:
			_stop_audio()
			screen = Screen.LIBRARY
		Screen.SETTINGS:
			screen = Screen.LIBRARY
		Screen.RESULTS:
			open_group = {}
			screen = Screen.LIBRARY
		Screen.LIBRARY:
			if not open_group.is_empty():
				open_group = {}
			elif tab == TAB_MUSIC and search_open:
				_close_search()
			elif tab == TAB_MUSIC and music_tab == 2 and open_playlist >= 0:
				open_playlist = -1
				_apply_filter()
			elif tab != TAB_HOME:
				tab = TAB_HOME
				home_dirty = true
			else:
				get_tree().quit()

func _resize() -> void:
	viewport_size = get_viewport_rect().size
	hit_y = viewport_size.y - HIT_MARGIN
	ui_off = maxf(0.0, (viewport_size.y - 1920.0) / 2.0)
	top_inset = 0.0
	var win_w := float(DisplayServer.window_get_size().x)
	if win_w > 0.0:
		var safe := DisplayServer.get_display_safe_area()
		top_inset = maxf(0.0, float(safe.position.y)) * viewport_size.x / win_w
	if search_edit != null:
		search_edit.position = Vector2(55, 140 + top_inset)
		search_edit.size = Vector2(viewport_size.x - 375.0, 105)
	queue_redraw()

func _process(delta: float) -> void:
	if screen == Screen.GAME and started and not paused and not finished:
		song_time += delta * play_rate
		_sync_audio()
		_update_notes()
	if previewing and (screen != Screen.PREPARE or not player.playing):
		previewing = false
	if screen == Screen.LIBRARY and tab == TAB_MUSIC and press_id == -999 and absf(scroll_vel) > 12.0:
		scroll_y += scroll_vel * delta
		scroll_vel *= exp(-3.0 * delta)   # frena poco a poco: desplazamiento con inercia
		if _clamp_scroll():
			scroll_vel = 0.0
	elif press_id == -999:
		scroll_vel = 0.0
	if name_edit != null:
		name_edit.visible = overlay == "newlist"
	if search_edit != null:
		search_edit.visible = screen == Screen.LIBRARY and tab == TAB_MUSIC and search_open and open_group.is_empty() and overlay == ""
	if judgement_time > 0.0:
		judgement_time -= delta
	if combo_pop > 0.0:
		combo_pop -= delta
	if banner_time > 0.0:
		banner_time -= delta
	var bg_target := 1.0 if infinite_run and (stars >= 3 or crowns > 0) else 0.0
	bg_blend = move_toward(bg_blend, bg_target, delta * 0.8)
	if lap_banner_time > 0.0:
		lap_banner_time -= delta
	if life_menu_lock > 0.0:
		life_menu_lock -= delta
	if grace_time > 0.0 and not paused:
		grace_time -= delta
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
	# La posición del audio va en segundos de la canción; latencia y mezcla van en segundos reales.
	var audio_time := player.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * play_rate + audio_offset
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
			var end_time: float = note.time + note.duration
			if not held and song_time < end_time - 0.12:
				_release_hold(note)
			elif song_time >= end_time:
				note.done = true
				note.holding = false
				_hit(note.lane, "PERFECT", 180, hit_y)
		elif note.type != "start" and song_time > note.time + HIT_LATE * play_rate:
			var miss_position: float = hit_y + (song_time - note.time) * speed
			note.done = true
			if note.type == "hold":   # la larga entera se queda atrás, apagada
				note.released = true
				note.release_time = note.time
			_miss(note.lane, miss_position)
	while first_idx < notes.size() and notes[first_idx].done and not _ghost_visible(notes[first_idx]):
		first_idx += 1
	_check_awards(false)
	if song_time > chart_end and not finished and infinite_run:
		_next_lap()
		return
	if song_time > chart_end and not finished:
		finished = true
		await get_tree().create_timer(0.7).timeout
		if screen == Screen.GAME:
			_stop_audio()
			_finish_run()
			screen = Screen.RESULTS

## Soltar una larga antes de tiempo NO cuesta vida: Great si la sostuviste al menos la mitad
## (el combo sigue), Good si la soltaste muy pronto (se rompe el combo). Lo que queda de la
## larga se queda atrás, apagada y sin poder tocarse.
# --- Modo Infinito -------------------------------------------------------
# Vuelta 1 (x1.0): 3 estrellas, a 1/3, 2/3 y al final. Vuelta 2 (x1.5): 2 coronas, a la
# mitad y al final. Vuelta 3 (x2.0): la 3ª corona al terminar. Luego +0.5x por vuelta.

func _lap_awards(n: int) -> Array:
	match n:
		1: return [[1.0 / 3.0, "star"], [2.0 / 3.0, "star"], [1.0, "star"]]
		2: return [[0.5, "crown"], [1.0, "crown"]]
		3: return [[1.0, "crown"]]
	return []

func _check_awards(final: bool) -> void:
	if not infinite_run:
		return
	var frac := clampf(song_time / maxf(0.1, chart_end), 0.0, 1.0)
	var list := _lap_awards(lap)
	while award_idx < list.size():
		var at: float = list[award_idx][0]
		if at < 0.999:
			if frac < at: break
		elif not final:
			break
		_grant_award(String(list[award_idx][1]))
		award_idx += 1

func _grant_award(kind: String) -> void:
	score += 500
	if kind == "star":
		stars += 1
		banner_text = "ESTRELLA %d/3" % stars
	else:
		crowns += 1
		banner_text = "CORONA %d/3" % crowns
	banner_kind = kind
	banner_time = 1.8
	_store_infinite_best()

func _next_lap() -> void:
	_check_awards(true)
	lap += 1
	lap_factor = 1.0 + 0.5 * float(lap - 1)
	lap_banner_text = "VUELTA %d · x%.1f" % [lap, lap_factor]
	lap_banner_time = 2.4
	play_rate = 1.0 + LAP_SONG_STEP * float(lap - 1)   # la canción suena un poco más rápido
	player.pitch_scale = play_rate
	# Velocidad real de caída = BASE * mult * lap_factor (como antes); aquí va por segundo de canción.
	speed = BASE_SPEED * _effective_mult() * lap_factor / play_rate
	_store_infinite_best()
	ahead = hit_y / speed + 0.15
	lead_in = maxf(0.0, hit_y / speed + 0.05 - first_note_time) if use_lead_in else 0.0
	for n in notes:
		if n.type == "start":
			continue
		n.done = false; n.holding = false; n.released = false; n.input_id = -999
	_assign_tap_heights()
	first_idx = 0
	active_inputs.clear()
	player.stop(); audio_started = false
	song_time = -(lead_in + 0.6)
	award_idx = 0

## Guarda el mejor resultado del Infinito (estrellas, coronas, vuelta y puntos) para esta
## canción y dificultad. Se llama al ganar cada premio y cada vuelta, así no se pierde nada
## aunque salgas antes de que termine la partida. Solo sube, nunca baja.
func _store_infinite_best() -> void:
	if not infinite_run or current_song.is_empty():
		return
	var key := _song_key(current_song) + "|inf"
	var old: Dictionary = bests.get(key, {})
	var pen := roundi(score * _lives_mult(run_lives)) if run_lives > 0 else score
	var nb := {
		"stars": maxi(stars, int(old.get("stars", 0))),
		"crowns": maxi(crowns, int(old.get("crowns", 0))),
		"laps": maxi(lap, int(old.get("laps", 0))),
		"score": maxi(pen, int(old.get("score", 0))),
	}
	if nb.stars > int(old.get("stars", 0)) or nb.crowns > int(old.get("crowns", 0)) or nb.laps > int(old.get("laps", 0)) or nb.score > int(old.get("score", 0)):
		run_record = true
	bests[key] = nb
	_save_settings()

func _finish_infinite() -> void:
	_store_infinite_best()
	# Penalización por vidas extra (igual que en Vidas): 3 vidas sin penalización.
	run_mult = _lives_mult(run_lives) if run_lives > 0 else 1.0
	score = roundi(score * run_mult)

func _star_poly(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rad := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
	return pts

func _crown_poly(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-r, r * 0.7), c + Vector2(-r, -r * 0.55), c + Vector2(-r * 0.5, r * 0.05), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.5, r * 0.05), c + Vector2(r, -r * 0.55), c + Vector2(r, r * 0.7)])

func _draw_award(kind: String, c: Vector2, r: float, earned: bool) -> void:
	var fill := Color(1.0, 0.8, 0.2) if earned else Color(0.45, 0.5, 0.6, 0.5)
	var edge := Color(0.3, 0.18, 0.0, 0.9) if earned else Color(0.3, 0.35, 0.45, 0.4)
	if kind == "star":
		draw_colored_polygon(_star_poly(c, r * 1.2), edge)
		draw_colored_polygon(_star_poly(c, r), fill)
	else:
		draw_colored_polygon(_crown_poly(c, r * 1.2), edge)
		draw_colored_polygon(_crown_poly(c, r), fill)

func _release_hold(note: Dictionary) -> void:
	var frac: float = clampf((song_time - float(note.time)) / maxf(0.05, float(note.duration)), 0.0, 1.0)
	note.done = true
	note.holding = false
	note.released = true
	note.release_time = song_time
	if frac >= 0.5:
		_hit(note.lane, "GREAT", 120, hit_y)
	else:
		_hit(note.lane, "GOOD", 50, hit_y)
		combo = 0

func _ghost_visible(note: Dictionary) -> bool:
	if not note.get("released", false):
		return false
	return song_time < float(note.time) + float(note.duration) + (viewport_size.y - hit_y) / speed + 0.1

func _unhandled_input(event: InputEvent) -> void:
	# En Android cada toque llega dos veces: como InputEventScreenTouch y como un
	# clic de ratón emulado (device = -1). Nos quedamos solo con el toque real.
	# En móvil no hay ratón real: se ignora todo evento de ratón (son copias emuladas del toque).
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and (OS.has_feature("mobile") or event.device == InputEvent.DEVICE_ID_EMULATION):
		return
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
		if life_menu or finished:
			return
		if event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not resume_pending:
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
	if screen == Screen.PREPARE and overlay != "":
		_overlay_tap(pos)
		return
	if screen == Screen.SETTINGS and _nav_tap(pos):
		return
	if screen == Screen.PREPARE or screen == Screen.RESULTS or screen == Screen.SETTINGS:
		pos.y -= ui_off
	if screen == Screen.PREPARE:
		if Rect2(100, 1640, viewport_size.x - 200, 145).has_point(pos): _start_game()
		elif Rect2(35, 45, 180, 95).has_point(pos): _stop_audio(); screen = Screen.LIBRARY
		elif Rect2(viewport_size.x - 365, 45, 330, 95).has_point(pos): _toggle_preview()
		elif Rect2(235, 45, viewport_size.x - 620, 95).has_point(pos): overlay = "addto"
		elif Rect2(100, 800, 190, 110).has_point(pos): _adjust_diff(-1)
		elif Rect2(viewport_size.x - 290, 800, 190, 110).has_point(pos): _adjust_diff(1)
		elif Rect2(100, 950, 190, 120).has_point(pos): _adjust_speed(-SPEED_STEP)
		elif Rect2(viewport_size.x - 290, 950, 190, 120).has_point(pos): _adjust_speed(SPEED_STEP)
		elif Rect2(310, 950, viewport_size.x - 620, 120).has_point(pos): speed_auto = not speed_auto; _save_settings()
		elif _mode_rect(0).has_point(pos): lives_mode = false; infinite_mode = false; _save_settings()
		elif _mode_rect(1).has_point(pos): lives_mode = true; infinite_mode = false; _save_settings()
		elif _mode_rect(2).has_point(pos): lives_mode = true; infinite_mode = true; _save_settings()
		elif lives_mode and Rect2(130, 1340, 170, 100).has_point(pos): _adjust_lives(-1)
		elif lives_mode and Rect2(viewport_size.x - 300, 1340, 170, 100).has_point(pos): _adjust_lives(1)
	elif screen == Screen.GAME:
		if finished:
			return
		if life_menu:
			pos.y -= ui_off
			if life_menu_lock <= 0.0:
				if Rect2(170, 760, viewport_size.x - 340, 135).has_point(pos): _give_up()
				elif Rect2(170, 930, viewport_size.x - 340, 135).has_point(pos): _continue_after_life()
			return
		if resume_pending:
			var rl: int = clampi(int(pos.x / (viewport_size.x / LANES)), 0, LANES - 1)
			active_inputs[input_id] = rl
			_try_hit(rl, input_id)
			return
		if Rect2(viewport_size.x - 145, 35 + top_inset, 110, 100).has_point(pos):
			_set_paused(not paused)
			return
		if paused:
			pos.y -= ui_off
			if Rect2(170, 760, viewport_size.x - 340, 135).has_point(pos): _set_paused(false)
			elif Rect2(170, 930, viewport_size.x - 340, 135).has_point(pos): _go_library()
			return
		var lane: int = clampi(int(pos.x / (viewport_size.x / LANES)), 0, LANES - 1)
		active_inputs[input_id] = lane
		_try_hit(lane, input_id)
	elif screen == Screen.SETTINGS:
		if Rect2(80, 330, viewport_size.x - 160, 180).has_point(pos):
			show_bg = not show_bg; _reload_bg(); _save_settings()
		elif Rect2(80, 870, viewport_size.x - 160, 180).has_point(pos):
			show_thumbs = not show_thumbs; _save_settings()
		elif show_bg and Rect2(130, 690, 170, 110).has_point(pos): _adjust_bg(-0.05)
		elif show_bg and Rect2(viewport_size.x - 300, 690, 170, 110).has_point(pos): _adjust_bg(0.05)
	elif screen == Screen.RESULTS:
		if Rect2(110, 1400, viewport_size.x - 220, 135).has_point(pos): _start_game()
		elif Rect2(110, 1570, viewport_size.x - 220, 120).has_point(pos): open_group = {}; screen = Screen.LIBRARY

## Un tap no debe solaparse con la siguiente nota de su carril.
func _assign_tap_heights() -> void:
	var next_time := {}
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		if n.type == "start":
			continue
		n.height = NORMAL_HEIGHT
		if n.type == "tap" and next_time.has(n.lane):
			n.height = clampf((next_time[n.lane] - n.time) * speed - 6.0, 50.0, NORMAL_HEIGHT)
		next_time[n.lane] = n.time

func _start_game() -> void:
	_stop_audio()
	screen = Screen.GAME
	if not current_song.is_empty():
		last_played = {"id": String(current_song.get("set_id", "demo")), "version": String(current_song.get("version", ""))}
		_save_settings()
	infinite_run = infinite_mode and lives_mode
	lap = 1; lap_factor = 1.0; award_idx = 0; stars = 0; crowns = 0
	banner_time = 0.0; lap_banner_time = 0.0; bg_blend = 0.0
	play_rate = 1.0; player.pitch_scale = 1.0; run_record = false
	speed = BASE_SPEED * _effective_mult()
	ahead = hit_y / speed + 0.15
	# Que la primera nota entre desde arriba justo al empezar.
	lead_in = maxf(0.0, hit_y / speed + 0.05 - first_note_time) if use_lead_in else 0.0
	notes.clear()
	for data in chart:
		var note: Dictionary = data.duplicate(true)
		note.done = false
		note.holding = false
		note.input_id = -999
		note.height = NORMAL_HEIGHT
		notes.append(note)
	_assign_tap_heights()
	first_idx = 0
	player.stream = audio_stream
	active_inputs.clear(); effects.clear()
	song_time = -lead_in; started = false; paused = false; finished = false
	score = 0; combo = 0; max_combo = 0; hits = 0; misses = 0
	perfects = 0; greats = 0; goods = 0; empties = 0
	run_lives = lives_setting if lives_mode else 0
	lives_left = run_lives
	life_menu = false; life_menu_lock = 0.0; resume_pending = false; resume_idxs = []; grace_time = 0.0
	failed = false; fail_text = ""; run_mult = 1.0

func _try_hit(lane: int, input_id: int) -> void:
	if resume_pending:
		_resume_with(lane, input_id)
		return
	if paused or finished:
		return
	if not started:
		for note in notes:
			if note.type == "start" and note.lane == lane and not note.done:
				note.done = true; started = true; song_time = -lead_in; audio_started = false
				_hit(lane, "COMENZAR", 0, hit_y)
				return
		_effect(lane, hit_y, Color(1.0, 0.15, 0.18, 0.84))
		return
	# La tecla se dibuja con su borde inferior en la línea de golpeo al llegar su hora,
	# así que el cuerpo (alto NORMAL_HEIGHT) se ve ANTES. Se puede tocar en cualquier
	# parte del cuerpo: la ventana "temprana" equivale al tiempo que tarda en caer su alto.
	var best: Dictionary = {}
	var best_diff := 999.0
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > 0.6: break
		if note.done or note.type == "start" or note.lane != lane: continue
		var early: float = clampf(float(note.height) / speed, 0.2, 0.6)
		var signed_diff: float = song_time - note.time
		if signed_diff < -early * play_rate or signed_diff > HIT_LATE * play_rate: continue
		best_diff = abs(signed_diff); best = note
		break  # la más antigua pendiente del carril
	if best.is_empty():
		combo = 0; empties += 1; _set_judgement("VACÍO", 0.4)
		_effect(lane, hit_y, Color(1.0, 0.15, 0.18, 0.84))
		_lose_life()
		return
	if best.type == "hold":
		best.holding = true; best.input_id = input_id
		_effect(lane, hit_y, Color(1, 1, 1, 0.82))
	else:
		best.done = true
		var judgement := "PERFECT" if best_diff <= PERFECT_WINDOW * play_rate else ("GREAT" if best_diff <= GREAT_WINDOW * play_rate else "GOOD")
		var points := 100 if judgement == "PERFECT" else (75 if judgement == "GREAT" else 50)
		_hit(lane, judgement, points, hit_y)

func _hit(lane: int, text: String, points: int, effect_y: float) -> void:
	hits += 1; combo += 1; max_combo = max(max_combo, combo); score += points + min(combo, 50)
	_set_judgement(text, 0.55); combo_pop = 0.18
	match text:
		"PERFECT": perfects += 1
		"GREAT": greats += 1
		"GOOD": goods += 1
	_effect(lane, effect_y, Color(1, 1, 1, 0.82))

func _set_judgement(text: String, duration: float) -> void:
	last_judgement = text; judgement_time = duration; judgement_total = duration

func _judgement_color(text: String) -> Color:
	match text:
		"PERFECT": return Color(1.0, 0.78, 0.12)
		"GREAT": return Color(0.05, 0.82, 0.95)
		"GOOD": return Color(0.3, 0.85, 0.45)
		"MISS", "VACÍO": return Color(1.0, 0.25, 0.3)
	return Color.WHITE

func _miss(lane: int, effect_y: float) -> void:
	misses += 1; combo = 0; _set_judgement("MISS", 0.6)
	_effect(lane, effect_y, Color(1.0, 0.15, 0.18, 0.84))
	_lose_life()

# --- Modo Vidas ----------------------------------------------------------

## Cada fallo (nota que se va, hold soltado, toque en vacío) cuesta una vida.
## Con vidas restantes: pausa y menú (rendirse / continuar). Sin vidas: fin de la partida.
func _lose_life() -> void:
	if run_lives <= 0 or finished or life_menu or grace_time > 0.0:
		return
	# Con N vidas se pueden fallar N veces y seguir; el fallo N+1 (con 0 vidas) termina.
	if lives_left <= 0:
		_game_over("SIN VIDAS")
	else:
		lives_left -= 1
		life_menu = true
		life_menu_lock = 0.7
		_set_paused(true)

func _game_over(text: String) -> void:
	failed = true; fail_text = text; finished = true
	await get_tree().create_timer(0.9).timeout
	if screen == Screen.GAME:
		_stop_audio()
		_finish_run()
		screen = Screen.RESULTS

func _give_up() -> void:
	life_menu = false; paused = false
	failed = true; fail_text = "TE RENDISTE"; finished = true
	_stop_audio()
	_finish_run()
	screen = Screen.RESULTS

func _continue_after_life() -> void:
	life_menu = false
	# Las notas sostenidas en curso se perdonan: el dedo ya no está en la pantalla.
	for n in notes:
		if n.holding:
			n.holding = false
			n.done = true
	active_inputs.clear()
	# La siguiente nota pendiente se marca como "Continuar": al tocarla se cuenta como
	# esa nota y la canción sigue desde ahí.
	resume_idxs = []
	var first_pending := -1
	for i in range(first_idx, notes.size()):
		if not notes[i].done and notes[i].type != "start":
			first_pending = i
			break
	if first_pending < 0:
		grace_time = GRACE_AFTER_CONTINUE
		_set_paused(false)
		return
	# Todas las notas del mismo instante (acorde) hay que tocarlas para seguir.
	var t0: float = notes[first_pending].time
	for j in range(first_pending, notes.size()):
		if float(notes[j].time) - t0 > 0.03:
			break
		if not notes[j].done and notes[j].type != "start":
			resume_idxs.append(j)
	# La escena queda congelada tal como se verá al seguir: la nota a retomar y las
	# que vienen detrás se ven en su sitio, así puedes colocar los dedos antes de tocar.
	song_time = t0 - RESUME_BACKOFF
	resume_pending = true   # sigue pausado hasta que se toquen esas teclas

func _resume_with(lane: int, input_id: int) -> void:
	var tapped := false
	for k in resume_idxs:
		var n: Dictionary = notes[k]
		if n.done or n.holding or int(n.lane) != lane:
			continue
		if n.type == "hold":
			n.holding = true; n.input_id = input_id
		else:
			n.done = true
		_effect(lane, hit_y, Color(1, 1, 1, 0.82))
		tapped = true
		break
	if not tapped:
		return
	for k in resume_idxs:
		if not notes[k].done and not notes[k].holding:
			return   # faltan teclas del acorde
	resume_pending = false; resume_idxs = []
	grace_time = GRACE_AFTER_CONTINUE
	_set_paused(false)
	if audio_stream != null and audio_started:
		player.seek(maxf(0.0, song_time))

## Puntos x1.00 con 3 vidas; cada vida extra resta ~7,1 % hasta x0.50 con 10.
func _lives_mult(n: int) -> float:
	return 1.0 - float(n - LIVES_MIN) * 0.5 / float(LIVES_MAX - LIVES_MIN)

func _adjust_lives(delta: int) -> void:
	lives_setting = clampi(lives_setting + delta, LIVES_MIN, LIVES_MAX)
	_save_settings()

func _mode_rect(i: int) -> Rect2:
	var bw := (viewport_size.x - 240.0 - 32.0) / 3.0
	return Rect2(110.0 + i * (bw + 16.0), 1190, bw, 120)

## Vidas como barras horizontales gruesas (las restantes encendidas, de izquierda a derecha).
func _draw_lives_bars(x: float, y: float, bar_w: float, bar_h: float, gap: float) -> void:
	for i in run_lives:
		var r := Rect2(x + i * (bar_w + gap), y, bar_w, bar_h)
		draw_rect(r.grow(3.0), Color(0.04, 0.16, 0.32, 0.9))
		draw_rect(r, Color(1.0, 0.3, 0.4) if i < lives_left else Color(0.4, 0.46, 0.56, 0.6))

func _effect(lane: int, effect_y: float, color: Color) -> void:
	effects.append({"lane":lane, "y":effect_y, "color":color, "time":0.20, "duration":0.20})

# --- Biblioteca e importación -------------------------------------------

func _refresh_library() -> void:
	var entries: Array = [DEMO_ENTRY]
	entries.append_array(OsuImporter.scan_library())
	groups = _group_entries(entries)
	open_group = {}
	home_dirty = true
	_apply_filter()

## Agrupa las dificultades de un mismo .osz (misma carpeta) en una sola canción.
func _group_entries(entries: Array) -> Array:
	var out: Array = []
	var by_id := {}
	for e in entries:
		var id: String = e.get("set_id", "demo")
		if not by_id.has(id):
			var g := {"id": id, "title": e.title, "artist": e.artist, "creator": e.get("creator", ""), "entries": [], "mtime": 0}
			by_id[id] = g
			out.append(g)
		by_id[id].entries.append(e)
	for g in out:
		for e in g.entries:
			if not e.get("demo", false) and e.has("osu_path"):
				g.mtime = maxi(int(g.mtime), int(FileAccess.get_modified_time(String(e.osu_path))))
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
	if music_tab == 2:
		view_groups = _playlist_view()
	else:
		var base: Array = groups
		if music_tab == 1:
			base = groups.filter(func(g): return favorites.has(g.id))
		if not words.is_empty():
			base = base.filter(func(g): return _group_matches(g, words))
		view_groups = _sorted(base)
	scroll_y = 0.0
	scroll_vel = 0.0
	_clamp_scroll()

func _sorted(base: Array) -> Array:
	var out: Array = base.duplicate()
	match sort_mode:
		1:
			out.sort_custom(func(a, b):
				if a.artist != b.artist:
					return String(a.artist).naturalnocasecmp_to(String(b.artist)) < 0
				return String(a.title).naturalnocasecmp_to(String(b.title)) < 0)
		2:
			out.sort_custom(func(a, b): return int(a.get("mtime", 0)) > int(b.get("mtime", 0)))
		3:
			out.sort_custom(func(a, b):
				if a.entries.size() != b.entries.size():
					return a.entries.size() > b.entries.size()
				return String(a.title).naturalnocasecmp_to(String(b.title)) < 0)
		_:
			out.sort_custom(func(a, b): return String(a.title).naturalnocasecmp_to(String(b.title)) < 0)
	# El mapa de prueba siempre al final.
	var demo: Array = out.filter(func(g): return g.id == "demo")
	out = out.filter(func(g): return g.id != "demo")
	out.append_array(demo)
	return out

func _toggle_favorite(id: String) -> void:
	if favorites.has(id):
		favorites.erase(id)
	else:
		favorites[id] = true
	var keep := scroll_y
	_apply_filter()
	scroll_y = keep
	_clamp_scroll()
	_save_settings()

## Miniatura de una canción: la imagen de fondo de su primera dificultad que la tenga.
## Se decodifica pequeña y de una en una por fotograma para no trabar el scroll.
func _group_thumb(g: Dictionary) -> Texture2D:
	var path := ""
	for e in g.entries:
		var bp := String(e.get("bg_path", ""))
		if bp != "":
			path = bp
			break
	if path == "":
		return null
	if thumb_cache.has(path):
		return thumb_cache[path]
	if thumb_budget <= 0:
		return null
	thumb_budget -= 1
	if thumb_cache.size() >= 60:
		thumb_cache.erase(thumb_cache.keys()[0])
	var tex: Texture2D = OsuImporter.load_image(path, 360)
	thumb_cache[path] = tex
	return tex

func _draw_heart(c: Vector2, sz: float, color: Color) -> void:
	draw_circle(c + Vector2(-0.24 * sz, -0.12 * sz), 0.30 * sz, color)
	draw_circle(c + Vector2(0.24 * sz, -0.12 * sz), 0.30 * sz, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-0.52 * sz, -0.01 * sz), c + Vector2(0.52 * sz, -0.01 * sz), c + Vector2(0.0, 0.58 * sz)]), color)

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
		if library_dir != "":   # copia de respaldo en la carpeta de canciones
			var bdir := library_dir.path_join(BACKUP_NAME)
			DirAccess.make_dir_recursive_absolute(bdir)
			var bid := FileAccess.get_md5(path).substr(0, 10)
			_backup_copy(path, bdir, bid, "%s [%s].osz" % [OsuImporter.safe_name(String(result.title)), bid])
		_refresh_library()
		_show_status("Importado: %s (%d dificultades)" % [result.title, result.count], false)
	else:
		_show_status(result.error, true)

# --- Carpeta de canciones (respaldo y recarga) -----------------------------
# <carpeta>/Por importar : se dejan aquí los .osz; al recargar se importan y se mueven.
# <carpeta>/Importadas   : copia de todos los .osz importados; si reinstalas la app,
#                          elegir la carpeta y recargar restaura las canciones.

func _default_library_dir() -> String:
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs == "":
		docs = OS.get_user_data_dir()
	return docs.path_join("TilesFOSS")

func _set_library_dir(path: String) -> void:
	if path == "" or path.begins_with("content://"):
		library_dir = _default_library_dir()
		_save_settings()
		_show_status("Android no deja usar esa carpeta. Se usa la de por defecto: %s" % library_dir, true, 8.0)
		return
	library_dir = path
	progress_merged = false
	_merge_progress_file()
	progress_merged = true
	_save_settings()
	_apply_filter()
	_show_status("Carpeta de canciones: %s" % path, false)

func _osz_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.to_lower().ends_with(".osz"):
			out.append(f)
	return out

## Copia un .osz a la carpeta de respaldo (sin duplicar). true si queda guardado.
func _backup_copy(src: String, backup_dir: String, id: String, name: String) -> bool:
	var target := backup_dir.path_join(name)
	if FileAccess.file_exists(target):
		if FileAccess.get_md5(target).substr(0, 10) == id:
			return true
		target = backup_dir.path_join("%s_%s" % [id, name])
		if FileAccess.file_exists(target):
			return true
	if DirAccess.copy_absolute(src, target) != OK:
		var bytes := FileAccess.get_file_as_bytes(src)
		if bytes.is_empty():
			return false
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			return false
		out.store_buffer(bytes)
		out.close()
	return FileAccess.file_exists(target)

func _progress_path() -> String:
	return library_dir.path_join(PROGRESS_FILE) if library_dir != "" else ""

## Copia de los récords, listas y favoritas en la carpeta de canciones (junto a
## "Por importar" e "Importadas"), para recuperarlos al reinstalar la app.
func _save_progress_file() -> void:
	var path := _progress_path()
	if path == "" or not DirAccess.dir_exists_absolute(library_dir):
		return
	if not progress_merged:
		progress_merged = true
		_merge_progress_file()   # antes de escribir, une lo que ya había en el archivo
	var cfg := ConfigFile.new()
	for key in bests:
		cfg.set_value("best", key, bests[key])
	cfg.set_value("library", "playlists", playlists)
	cfg.set_value("library", "favorites", favorites.keys())
	cfg.set_value("library", "last_id", String(last_played.get("id", "")))
	cfg.set_value("library", "last_version", String(last_played.get("version", "")))
	cfg.save(path)

## Une lo que haya en progreso.cfg con lo actual (nunca baja un récord). true si cambió algo.
func _merge_progress_file() -> bool:
	var path := _progress_path()
	if path == "" or not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	var changed := false
	if cfg.has_section("best"):
		for key in cfg.get_section_keys("best"):
			var v = cfg.get_value("best", key)
			if not (v is Dictionary):
				continue
			if not bests.has(key):
				bests[key] = v
				changed = true
				continue
			var cur: Dictionary = bests[key]
			var merged: Dictionary = cur.duplicate()
			if String(key).ends_with("|inf"):
				for f in ["stars", "crowns", "laps", "score"]:
					merged[f] = maxi(int(cur.get(f, 0)), int(v.get(f, 0)))
			else:
				merged = (v if int(v.get("score", 0)) > int(cur.get("score", 0)) else cur).duplicate()
				merged["rank"] = maxi(int(cur.get("rank", 0)), int(v.get("rank", 0)))
			if JSON.stringify(merged, "", true) != JSON.stringify(cur, "", true):
				bests[key] = merged
				changed = true
	var pl = cfg.get_value("library", "playlists", [])
	if pl is Array:
		for p in pl:
			if not (p is Dictionary and p.has("name") and p.get("refs") is Array):
				continue
			var found := -1
			for i in playlists.size():
				if String(playlists[i].name) == String(p.name):
					found = i
			if found < 0:
				playlists.append({"name": String(p.name), "refs": (p.refs as Array).duplicate()})
				changed = true
			else:
				for r in p.refs:
					if not playlists[found].refs.has(r):
						playlists[found].refs.append(r)
						changed = true
	var fav_list = cfg.get_value("library", "favorites", [])
	if fav_list is Array:
		for fid in fav_list:
			if not favorites.has(String(fid)):
				favorites[String(fid)] = true
				changed = true
	if String(last_played.get("id", "")) == "" and String(cfg.get_value("library", "last_id", "")) != "":
		last_played = {"id": String(cfg.get_value("library", "last_id", "")), "version": String(cfg.get_value("library", "last_version", ""))}
		changed = true
	return changed

## Comprueba el permiso de archivos y crea las carpetas de trabajo. false si no hay acceso.
func _library_access_ok() -> bool:
	if library_dir == "":
		library_dir = _default_library_dir()
	# En Android 11+ la app puede crear la carpeta sin permiso, pero sin "acceso a todos
	# los archivos" no ve los .osz que no creó ella (los tuyos ni los de una instalación previa).
	if OS.has_feature("android") and not perm_asked:
		var has_all := false
		for perm in OS.get_granted_permissions():
			if String(perm).contains("MANAGE_EXTERNAL_STORAGE"):
				has_all = true
		if not has_all:
			perm_asked = true
			OS.request_permissions()
			_show_status("Concede \"acceso a todos los archivos\" a la app y vuelve a pulsar el botón.", true, 12.0)
			return false
	var inbox := library_dir.path_join(INBOX_NAME)
	var backup := library_dir.path_join(BACKUP_NAME)
	DirAccess.make_dir_recursive_absolute(inbox)
	DirAccess.make_dir_recursive_absolute(backup)
	if not DirAccess.dir_exists_absolute(inbox) or not DirAccess.dir_exists_absolute(backup):
		if OS.has_feature("android"):
			OS.request_permissions()
		_show_status("Sin acceso a la carpeta. Concede \"acceso a todos los archivos\" a la app y pulsa el botón otra vez.", true, 10.0)
		return false
	return true

## Id de 10 caracteres hexadecimales entre corchetes al final del nombre ("título [id].osz").
func _id_from_name(file_name: String) -> String:
	var a := file_name.rfind("[")
	var b := file_name.rfind("]")
	if a < 0 or b <= a:
		return ""
	var id := file_name.substr(a + 1, b - a - 1)
	return id if id.length() == 10 and id.is_valid_hex_number() else ""

func _zip_dir(dir: String, target: String) -> bool:
	var zp := ZIPPacker.new()
	if zp.open(target) != OK:
		return false
	var any := false
	for f in DirAccess.get_files_at(dir):
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(f))
		if bytes.is_empty():
			continue
		zp.start_file(f)
		zp.write_file(bytes)
		zp.close_file()
		any = true
	zp.close()
	return any and FileAccess.file_exists(target)

## Guarda en "Importadas" un .osz de cada canción que todavía no tenga copia.
func _export_library() -> void:
	if syncing:
		return
	syncing = true
	if not _library_access_ok():
		syncing = false
		return
	_save_settings()   # guarda la carpeta (une antes progreso.cfg si ya existía)
	var backup := library_dir.path_join(BACKUP_NAME)
	var have := "\n".join(_osz_files(backup))
	var todo: Array = []
	var total := 0
	for g in groups:
		if g.id == "demo":
			continue
		total += 1
		if not have.contains("[%s]" % g.id):
			todo.append(g)
	var done := 0
	var failed := 0
	for g in todo:
		_show_status("Exportando %d/%d..." % [done + 1, todo.size()], false, 60.0)
		await get_tree().process_frame
		var osz_name := "%s [%s].osz" % [OsuImporter.safe_name(String(g.title)), g.id]
		if _zip_dir(OsuImporter.SONGS_DIR.path_join(String(g.id)), backup.path_join(osz_name)):
			done += 1
		else:
			failed += 1
	var msg := "Exportadas %d canciones nuevas (%d ya tenían copia)" % [done, total - todo.size()]
	if failed > 0:
		msg += ", %d con error" % failed
	if total == 0:
		msg = "No hay canciones importadas para exportar."
	_show_status(msg, failed > 0, 8.0)
	syncing = false

func _sync_folder() -> void:
	if syncing:
		return
	syncing = true
	if not _library_access_ok():
		syncing = false
		return
	var inbox := library_dir.path_join(INBOX_NAME)
	var backup := library_dir.path_join(BACKUP_NAME)
	progress_merged = true
	if _merge_progress_file():   # tras reinstalar: recupera récords, listas y favoritas
		_apply_filter()
	_save_settings()
	var backup_files := _osz_files(backup)
	var inbox_files := _osz_files(inbox)
	var total := backup_files.size() + inbox_files.size()
	var done := 0
	var restored := 0
	var imported := 0
	var failed := 0
	# 1) Restaurar lo que esté en Importadas y no esté en la biblioteca (reinstalación).
	for f in backup_files:
		done += 1
		var bpath := backup.path_join(f)
		var fid := _id_from_name(f)
		var rid := fid if fid != "" else FileAccess.get_md5(bpath).substr(0, 10)
		if not DirAccess.dir_exists_absolute(OsuImporter.SONGS_DIR.path_join(rid)):
			_show_status("Restaurando %d/%d..." % [done, total], false, 60.0)
			await get_tree().process_frame
			if OsuImporter.import_osz(bpath, fid).ok:
				restored += 1
			else:
				failed += 1
	# 2) Importar lo nuevo de Por importar, guardarlo en Importadas y borrarlo de ahí.
	for f in inbox_files:
		done += 1
		var ipath := inbox.path_join(f)
		var id := FileAccess.get_md5(ipath).substr(0, 10)
		var good := DirAccess.dir_exists_absolute(OsuImporter.SONGS_DIR.path_join(id))
		if not good:
			_show_status("Importando %d/%d..." % [done, total], false, 60.0)
			await get_tree().process_frame
			good = OsuImporter.import_osz(ipath).ok
		if good:
			if _backup_copy(ipath, backup, id, f):
				DirAccess.remove_absolute(ipath)
			imported += 1
		else:
			failed += 1
	_refresh_library()
	var msg := "Listo: %d importadas, %d restauradas (vi %d en Por importar y %d en Importadas)" % [imported, restored, inbox_files.size(), backup_files.size()]
	if failed > 0:
		msg += ", %d con error" % failed
	if total == 0:
		msg = "No veo ningún .osz en \"%s\" ni en \"%s\" (%s). Deja ahí tus .osz y pulsa Recargar. Si ya están, falta el permiso: Ajustes de Android, Apps, Tiles FOSS, Permisos, Archivos, permitir administrar todos los archivos." % [INBOX_NAME, BACKUP_NAME, library_dir]
		failed = 1
	_show_status(msg, failed > 0, 14.0 if total == 0 else 8.0)
	syncing = false

func _on_files_dropped(files: PackedStringArray) -> void:
	if screen != Screen.LIBRARY:
		return
	for f in files:
		if f.to_lower().ends_with(".osz"):
			_import_osz(f)
		else:
			_show_status("Solo se admiten archivos .osz", true)

func _show_status(text: String, is_error: bool, seconds := 6.0) -> void:
	status_text = text; status_error = is_error; status_time = seconds

# --- Barra inferior (Inicio / Música / Archivos / Ajustes) ----------------

func _nav_rect(i: int) -> Rect2:
	var cw := viewport_size.x / 4.0
	return Rect2(i * cw, viewport_size.y - NAV_H, cw, NAV_H)

func _nav_active() -> int:
	return 3 if screen == Screen.SETTINGS else tab

func _nav_tap(pos: Vector2) -> bool:
	for i in 4:
		if _nav_rect(i).has_point(pos):
			_go_tab(i)
			return true
	return false

func _go_tab(i: int) -> void:
	open_group = {}
	overlay = ""
	scroll_vel = 0.0
	if i == 3:
		screen = Screen.SETTINGS
		return
	screen = Screen.LIBRARY
	tab = i
	home_dirty = true

func _draw_nav_icon(i: int, c: Vector2, s: float, col: Color) -> void:
	var lw := s * 0.28
	match i:
		0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.05), c + Vector2(0, -s), c + Vector2(s, -s * 0.05)]), col)
			draw_rect(Rect2(c.x - s * 0.7, c.y - s * 0.05, s * 1.4, s * 0.95), col)
		1:
			draw_circle(c + Vector2(-s * 0.4, s * 0.55), s * 0.42, col)
			draw_line(c + Vector2(s * 0.0, s * 0.55), c + Vector2(s * 0.0, -s * 0.85), col, lw)
			draw_line(c + Vector2(0, -s * 0.85), c + Vector2(s * 0.75, -s * 0.4), col, lw)
		2:
			draw_rect(Rect2(c.x - s, c.y - s * 0.4, s * 2.0, s * 1.25), col)
			draw_rect(Rect2(c.x - s, c.y - s * 0.75, s * 0.9, s * 0.4), col)
		_:
			draw_arc(c, s * 0.62, 0.0, TAU, 32, col, lw)
			for k in 8:
				var a := k * TAU / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.8, c + Vector2(cos(a), sin(a)) * s * 1.05, col, lw * 1.1)

## Altura del borde superior de la barra en la posición x: más alta en el centro.
func _nav_curve_y(x: float) -> float:
	var t := (x - viewport_size.x / 2.0) / (viewport_size.x / 2.0)
	return viewport_size.y - NAV_H + NAV_BULGE * t * t

func _draw_nav() -> void:
	draw_set_transform(Vector2.ZERO)
	var w := viewport_size.x
	var top := PackedVector2Array()
	var steps := 36
	for k in steps + 1:
		var px := w * k / steps
		top.append(Vector2(px, _nav_curve_y(px)))
	var body := top.duplicate()
	body.append(Vector2(w, viewport_size.y + 2.0))
	body.append(Vector2(0, viewport_size.y + 2.0))
	draw_colored_polygon(body, Color(0.05, 0.09, 0.17))
	draw_polyline(top, Color(0.2, 0.3, 0.45), 4.0)
	var labels := ["Inicio", "Música", "Archivos", "Ajustes"]
	var colors := [Color(0.22, 0.5, 0.95), Color(0.95, 0.36, 0.58), Color(0.97, 0.6, 0.2), Color(0.2, 0.75, 0.45)]
	var active := _nav_active()
	for i in 4:
		var r := _nav_rect(i)
		var cx := r.get_center().x
		var ytop := _nav_curve_y(cx)
		var on := i == active
		var rad := 44.0 if on else 38.0
		var cc := Vector2(cx, ytop + 58.0 - (8.0 if on else 0.0))
		var base: Color = colors[i]
		draw_circle(cc + Vector2(0, 5), rad, Color(0, 0, 0, 0.25))
		draw_circle(cc, rad, base)
		draw_arc(cc, rad - 5.0, PI * 1.12, PI * 1.88, 16, Color(1, 1, 1, 0.35), 5.0)
		if on:
			draw_arc(cc, rad + 3.0, 0.0, TAU, 40, Color.WHITE, 5.0)
		_draw_nav_icon(i, cc, 18.0 if on else 16.0, base.lerp(Color.WHITE, 0.85))
		_text_centered(labels[i], cx, ytop + 58.0 + 38.0 + 30.0, 28, Color.WHITE if on else Color(0.72, 0.8, 0.9))

# --- Listas de reproducción -------------------------------------------------

func _ref(e: Dictionary) -> String:
	return "%s|%s" % [e.get("set_id", "demo"), e.get("version", "")]

func _entry_by_ref(ref: String) -> Dictionary:
	for g in groups:
		for e in g.entries:
			if _ref(e) == ref:
				return e
	return {}

func _find_entry(set_id: String, version: String) -> Dictionary:
	return _entry_by_ref("%s|%s" % [set_id, version])

func _group_of(set_id: String) -> Dictionary:
	for g in groups:
		if g.id == set_id:
			return g
	return {}

func _set_music_tab(i: int) -> void:
	music_tab = i
	open_playlist = -1
	delete_armed = false
	_apply_filter()

func _playlist_view() -> Array:
	var words := search_query.strip_edges().to_lower().split(" ", false)
	var out: Array = []
	if open_playlist < 0 or open_playlist >= playlists.size():
		open_playlist = -1
		for i in playlists.size():
			var pname := String(playlists[i].name)
			var ok := true
			for wd in words:
				if not pname.to_lower().contains(wd):
					ok = false
			if ok:
				var n: int = playlists[i].refs.size()
				out.append({"playlist_idx": i, "id": "pl%d" % i, "title": pname, "artist": "1 canción" if n == 1 else "%d canciones" % n, "creator": "", "entries": []})
		return out
	for ref in playlists[open_playlist].refs:
		var e := _entry_by_ref(String(ref))
		if e.is_empty():
			continue
		var g := {"id": e.get("set_id", "demo"), "title": e.title, "artist": e.artist, "creator": e.get("creator", ""), "entries": [e], "in_playlist": true}
		if words.is_empty() or _group_matches(g, words):
			out.append(g)
	return out

func _create_playlist(pname: String) -> int:
	playlists.append({"name": pname, "refs": []})
	_save_settings()
	return playlists.size() - 1

func _toggle_in_playlist(pi: int, e: Dictionary) -> void:
	var refs: Array = playlists[pi].refs
	var r := _ref(e)
	if refs.has(r):
		refs.erase(r)
	else:
		refs.append(r)
	_save_settings()

func _setup_name_edit() -> void:
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Nombre de la lista"
	name_edit.max_length = 40
	name_edit.visible = false
	name_edit.add_theme_font_size_override("font_size", 38)
	name_edit.add_theme_color_override("font_color", Color(0.12, 0.22, 0.31))
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
	name_edit.add_theme_color_override("caret_color", Color(0.02, 0.62, 0.86))
	for style_name in ["normal", "focus", "read_only"]:
		var box := _box(Color(0.88, 0.94, 1), 22)
		box.content_margin_left = 26.0
		box.content_margin_right = 20.0
		name_edit.add_theme_stylebox_override(style_name, box)
	name_edit.text_submitted.connect(func(_t): _commit_newlist())
	add_child(name_edit)

func _open_newlist(then_add: bool) -> void:
	newlist_then_add = then_add
	overlay = "newlist"
	name_edit.text = ""
	name_edit.grab_focus.call_deferred()

func _commit_newlist() -> void:
	var pname := name_edit.text.strip_edges()
	if pname == "":
		return
	var pi := _create_playlist(pname)
	if newlist_then_add and not current_song.is_empty():
		_toggle_in_playlist(pi, current_song)
	name_edit.release_focus()
	overlay = "addto" if newlist_then_add else ""
	if music_tab == 2 and open_playlist < 0:
		_apply_filter()

func _close_overlay() -> void:
	name_edit.release_focus()
	if overlay == "newlist" and newlist_then_add:
		overlay = "addto"
	else:
		overlay = ""

func _overlay_layout() -> Dictionary:
	var px := 80.0
	var pw := viewport_size.x - 160.0
	var rows: Array = []
	var extra := {}
	var h := 0.0
	var py := 0.0
	if overlay == "sort":
		var n_sort := SORT_MODES.size()
		h = 160.0 + n_sort * 114.0 + 10.0
		py = (viewport_size.y - h) / 2.0
		for i in n_sort:
			rows.append(Rect2(px + 30, py + 140 + i * 114.0, pw - 60, 100))
	elif overlay == "addto":
		var n_pl := mini(playlists.size(), 6)
		h = 160.0 + (n_pl + 1) * 114.0 + 120.0
		py = (viewport_size.y - h) / 2.0
		for i in n_pl:
			rows.append(Rect2(px + 30, py + 140 + i * 114.0, pw - 60, 100))
		extra["new"] = Rect2(px + 30, py + 140 + n_pl * 114.0, pw - 60, 100)
		extra["close"] = Rect2(px + 30, py + h - 110, pw - 60, 90)
	else:
		h = 440.0
		py = (viewport_size.y - h) / 2.0 - 120.0
		var bw := (pw - 90.0) / 2.0
		extra["edit"] = Rect2(px + 40, py + 150, pw - 80, 100)
		extra["cancel"] = Rect2(px + 30, py + 300, bw, 100)
		extra["ok"] = Rect2(px + 60 + bw, py + 300, bw, 100)
	return {"panel": Rect2(px, py, pw, h), "rows": rows, "extra": extra}

func _draw_overlay() -> void:
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.62))
	var lay := _overlay_layout()
	var panel: Rect2 = lay.panel
	var ink := Color(0.12, 0.22, 0.31)
	var soft := Color(0.88, 0.94, 1)
	var accent := Color(0.04, 0.65, 0.88)
	_panel(panel, Color(0.97, 0.98, 1), 34)
	var title := "Ordenar por"
	if overlay == "addto":
		title = "Añadir a lista"
	elif overlay == "newlist":
		title = "Nueva lista"
	_text(title, Vector2(panel.position.x + 40, panel.position.y + 86), 44, ink)
	if overlay == "sort":
		for i in lay.rows.size():
			var r: Rect2 = lay.rows[i]
			_panel(r, accent if i == sort_mode else soft, 22)
			_text(SORT_MODES[i], Vector2(r.position.x + 36, r.get_center().y + 13), 36, Color.WHITE if i == sort_mode else ink)
	elif overlay == "addto":
		if not current_song.is_empty():
			_text(_fit("%s · %s" % [current_song.get("title", ""), current_song.get("version", "")], panel.size.x - 80, 26), Vector2(panel.position.x + 40, panel.position.y + 124), 26, Color(0.42, 0.52, 0.62))
		for i in lay.rows.size():
			var r2: Rect2 = lay.rows[i]
			var has: bool = playlists[i].refs.has(_ref(current_song))
			_panel(r2, soft, 22)
			_text(_fit(String(playlists[i].name), r2.size.x - 160, 36), Vector2(r2.position.x + 36, r2.get_center().y + 13), 36, ink)
			if has:
				var cc := Vector2(r2.end.x - 60, r2.get_center().y)
				draw_polyline(PackedVector2Array([cc + Vector2(-20, 0), cc + Vector2(-6, 16), cc + Vector2(22, -16)]), Color(0.1, 0.7, 0.45), 9.0)
		var ex: Dictionary = lay.extra
		_button(ex["new"], "+ Nueva lista", accent)
		_button(ex["close"], "Listo", Color(0.17, 0.25, 0.37))
		if playlists.size() > 6:
			_text("Solo se muestran las 6 primeras listas.", Vector2(panel.position.x + 40, panel.end.y - 125), 22, Color(0.42, 0.52, 0.62))
	else:
		var ex2: Dictionary = lay.extra
		var er: Rect2 = ex2["edit"]
		name_edit.position = er.position
		name_edit.size = er.size
		_button(ex2["cancel"], "Cancelar", Color(0.17, 0.25, 0.37))
		_button(ex2["ok"], "Crear", accent)

func _overlay_tap(pos: Vector2) -> void:
	var lay := _overlay_layout()
	var panel: Rect2 = lay.panel
	var ex: Dictionary = lay.extra
	if overlay == "sort":
		for i in lay.rows.size():
			if lay.rows[i].has_point(pos):
				sort_mode = i
				_save_settings()
				_apply_filter()
				overlay = ""
				return
		if not panel.has_point(pos):
			overlay = ""
	elif overlay == "addto":
		for i in lay.rows.size():
			if lay.rows[i].has_point(pos):
				_toggle_in_playlist(i, current_song)
				return
		if ex["new"].has_point(pos):
			_open_newlist(true)
		elif ex["close"].has_point(pos) or not panel.has_point(pos):
			overlay = ""
	else:
		if ex["cancel"].has_point(pos) or not panel.has_point(pos):
			_close_overlay()
		elif ex["ok"].has_point(pos):
			_commit_newlist()

# --- Biblioteca: lista de canciones con desplazamiento suave ------------------

func _list_bottom() -> float:
	return viewport_size.y - NAV_H

func _library_pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if pressed:
		press_id = input_id; press_pos = pos; dragged = false; scroll_vel = 0.0
		drag_ms = Time.get_ticks_msec()
	elif input_id == press_id:
		press_id = -999
		if not dragged:
			_library_tap(pos)
		elif Time.get_ticks_msec() - drag_ms > 90:
			scroll_vel = 0.0   # soltó el dedo parado: sin inercia

func _library_drag(pos: Vector2, relative: Vector2, input_id: int) -> void:
	if screen != Screen.LIBRARY or input_id != press_id or not open_group.is_empty() or overlay != "" or tab != TAB_MUSIC:
		return
	if not dragged and pos.distance_to(press_pos) > 24.0:
		dragged = true
	if dragged:
		var now := Time.get_ticks_msec()
		var dt := maxf(0.004, float(now - drag_ms) / 1000.0)
		drag_ms = now
		scroll_vel = clampf(lerpf(scroll_vel, -relative.y / dt, 0.4), -7000.0, 7000.0)
		scroll_y -= relative.y
		_clamp_scroll()

## Devuelve true si el límite recortó la posición (para frenar la inercia en los bordes).
func _clamp_scroll() -> bool:
	var content := view_groups.size() * (CARD_H + CARD_GAP)
	var before := scroll_y
	scroll_y = clampf(scroll_y, 0.0, maxf(0.0, content - (_list_bottom() - LIST_TOP) + 40.0))
	return not is_equal_approx(before, scroll_y)

func _library_tap(pos: Vector2) -> void:
	if overlay != "":
		_overlay_tap(pos)
		return
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
	if _nav_tap(pos):
		return
	if tab == TAB_HOME:
		_home_tap(pos)
	elif tab == TAB_FILES:
		_files_tap(pos)
	else:
		_music_tap(pos)

func _music_tap(pos: Vector2) -> void:
	var w := viewport_size.x
	var hy := 150.0 + top_inset
	if search_edit.visible and search_edit.get_global_rect().has_point(pos):
		return
	search_edit.release_focus()
	if search_open:
		if Rect2(w - 300, hy, 245, 95).has_point(pos):
			_close_search()
			return
	else:
		if Rect2(w - 300, 40 + top_inset, 245, 80).has_point(pos):
			_open_search()
			return
		if Rect2(55, hy, 130, 95).has_point(pos):
			_set_music_tab(0)
			return
		if Rect2(195, hy, 205, 95).has_point(pos):
			_set_music_tab(1)
			return
		if Rect2(410, hy, 160, 95).has_point(pos):
			_set_music_tab(2)
			return
		if Rect2(w - 440, hy, 385, 95).has_point(pos):
			if music_tab != 2:
				overlay = "sort"
			elif open_playlist < 0:
				_open_newlist(false)
			elif delete_armed:
				playlists.remove_at(open_playlist)
				open_playlist = -1
				delete_armed = false
				_save_settings()
				_apply_filter()
			else:
				delete_armed = true
			return
	if pos.y < LIST_TOP - 22.0 or pos.y > _list_bottom() or pos.x < 55.0 or pos.x > w - 55.0:
		return
	var offset := pos.y - LIST_TOP + scroll_y
	var idx := int(offset / (CARD_H + CARD_GAP))
	if offset >= 0.0 and fmod(offset, CARD_H + CARD_GAP) <= CARD_H and idx < view_groups.size():
		var g: Dictionary = view_groups[idx]
		if g.has("playlist_idx"):
			open_playlist = int(g.playlist_idx)
			delete_armed = false
			_apply_filter()
			return
		if pos.x > w - 55.0 - 140.0:   # zona del corazón / quitar de la lista
			if g.get("in_playlist", false):
				var keep := scroll_y
				playlists[open_playlist].refs.erase(_ref(g.entries[0]))
				_save_settings()
				_apply_filter()
				scroll_y = keep
				_clamp_scroll()
			else:
				_toggle_favorite(String(g.id))
			return
		if g.entries.size() == 1:
			_select_song(g.entries[0])
		else:
			open_group = g

# --- Inicio --------------------------------------------------------------------

func _rebuild_home() -> void:
	home_dirty = false
	home_records = []
	for key in bests:
		var k := String(key)
		var inf := false
		var lvl := 1
		if k.ends_with("|inf"):
			inf = true
			k = k.trim_suffix("|inf")
		var p := k.rfind("|d")
		if p > 0 and k.substr(p + 2).is_valid_int():
			lvl = int(k.substr(p + 2))
			k = k.substr(0, p)
		var sid := k.get_slice("|", 0)
		var ver := k.substr(sid.length() + 1)
		var e := _find_entry(sid, ver)
		if e.is_empty():
			continue
		var b: Dictionary = bests[key]
		home_records.append({"entry": e, "level": clampi(lvl, 0, DIFFICULTY_LEVELS.size() - 1), "inf": inf, "b": b})
	home_records.sort_custom(func(a, b): return int(a.b.get("score", 0)) > int(b.b.get("score", 0)))

const HOME_ROWS_Y := 975.0
const HOME_ROW_H := 120.0
const HOME_ROW_STEP := 134.0

func _home_row_count() -> int:
	var avail := viewport_size.y - NAV_H - top_inset - HOME_ROWS_Y - 10.0
	return clampi(int(avail / HOME_ROW_STEP), 1, 8)

func _home_tap(pos: Vector2) -> void:
	pos.y -= top_inset
	var x := 55.0
	var cw := viewport_size.x - 110.0
	var le := _find_entry(String(last_played.get("id", "")), String(last_played.get("version", "")))
	if not le.is_empty() and (Rect2(0, -top_inset, viewport_size.x, 620.0 + top_inset).has_point(pos) or Rect2(viewport_size.x / 2.0 - 220.0, 770, 440, 100).has_point(pos)):
		_select_song(le)
		return
	var n := mini(_home_row_count(), home_records.size())
	for i in n:
		if Rect2(x, HOME_ROWS_Y + i * HOME_ROW_STEP, cw, HOME_ROW_H).has_point(pos):
			var rec: Dictionary = home_records[i]
			diff_level = int(rec.level)
			if rec.inf:
				lives_mode = true
				infinite_mode = true
			_select_song(rec.entry)
			return

func _draw_home() -> void:
	if home_dirty:
		_rebuild_home()
	var w := viewport_size.x
	var x := 55.0
	var cw := w - 110.0
	var muted := Color(0.62, 0.75, 0.88)
	var ink := Color(0.12, 0.22, 0.31)
	var navy := Color(0.025, 0.05, 0.1)
	var le := _find_entry(String(last_played.get("id", "")), String(last_played.get("version", "")))
	var hero_h := 620.0 + top_inset
	# Imagen de la última canción (horizontal) ocupando la parte de arriba.
	if le.is_empty():
		draw_rect(Rect2(0, 0, w, hero_h), Color(0.08, 0.16, 0.3))
	else:
		var path := String(le.get("bg_path", ""))
		if path != home_tex_path:
			home_tex_path = path
			home_tex = OsuImporter.load_image(path, 1280) if path != "" else null
		if home_tex != null:
			_draw_cover(home_tex, Rect2(0, 0, w, hero_h))
		else:
			draw_rect(Rect2(0, 0, w, hero_h), _badge_color(le).darkened(0.3))
	# Degradados: arriba para leer el título y abajo para fundir con el fondo.
	var bands := 20
	for k in bands:
		var f := float(k) / bands
		draw_rect(Rect2(0, k * 9.0, w, 10.0), Color(navy.r, navy.g, navy.b, 0.55 * (1.0 - f)))
	var fade := 240.0
	for k in bands:
		var f2 := float(k + 1) / bands
		draw_rect(Rect2(0, hero_h - fade + k * fade / bands, w, fade / bands + 1.0), Color(navy.r, navy.g, navy.b, 0.98 * pow(f2, 1.7)))
	var title_pos := Vector2(55, 105 + top_inset)
	draw_string_outline(_font(), title_pos, "TILES FOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, 10, Color(0.02, 0.05, 0.12, 0.9))
	draw_string(_font(), title_pos, "TILES FOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, Color.WHITE)
	draw_set_transform(Vector2(0, top_inset))
	if le.is_empty():
		_text_centered("Aún no has jugado ninguna canción", w / 2, 690, 40, Color.WHITE)
		_text_centered("Elígela en la pestaña Música.", w / 2, 740, 28, muted)
	else:
		_text_centered(_fit(String(le.title), w - 100, 52), w / 2, 690, 52, Color.WHITE)
		_text_centered(_fit("%s · %s" % [le.artist, le.version], w - 100, 28), w / 2, 738, 28, muted)
		var box := _box(Color(1, 1, 1, 0.10), 50)
		box.border_width_left = 4
		box.border_width_right = 4
		box.border_width_top = 4
		box.border_width_bottom = 4
		box.border_color = Color(1, 1, 1, 0.6)
		draw_style_box(box, Rect2(w / 2.0 - 220.0, 770, 440, 100))
		_text_centered("Jugar", w / 2, 840, 54, Color.WHITE)
	_text("Tus mejores récords", Vector2(55, 945), 32, muted)
	if home_records.is_empty():
		_text(_fit("Juega en modo Vidas o Infinito para guardar récords.", cw, 28), Vector2(55, HOME_ROWS_Y + 55), 28, muted)
	var n := mini(_home_row_count(), home_records.size())
	for i in n:
		var rec: Dictionary = home_records[i]
		var e: Dictionary = rec.entry
		var b: Dictionary = rec.b
		var y := HOME_ROWS_Y + i * HOME_ROW_STEP
		_panel(Rect2(x, y, cw, HOME_ROW_H), Color(0.97, 0.98, 1), 24)
		if rec.inf:
			_panel(Rect2(x, y, 110, HOME_ROW_H), Color(0.5, 0.38, 0.92), 24)
			var n_cr := int(b.get("crowns", 0))
			var n_st := int(b.get("stars", 0))
			var kind := "crown" if n_cr > 0 else "star"
			var cnt := mini(n_cr if n_cr > 0 else n_st, 3)
			_text_centered("INF", x + 55, y + 46, 28, Color(1, 1, 1, 0.85))
			for k in cnt:
				_draw_award(kind, Vector2(x + 55 + (k - (cnt - 1) / 2.0) * 32.0, y + 84), 12.0, true)
		else:
			_panel(Rect2(x, y, 110, HOME_ROW_H), RANK_COLORS[int(b.get("rank", 0))], 24)
			_text_centered(String(RANKS[int(b.get("rank", 0))]), x + 55, y + 78, 52, Color.WHITE)
		_text(_fit(String(e.title), cw - 135 - 230, 32), Vector2(x + 135, y + 52), 32, ink)
		var sub := "%s · %s" % [e.version, DIFFICULTY_LEVELS[int(rec.level)].name]
		if rec.inf:
			sub += " · Infinito"
		_text(_fit(sub, cw - 135 - 230, 23), Vector2(x + 135, y + 92), 23, Color(0.42, 0.52, 0.62))
		var score_txt := str(int(b.get("score", 0)))
		var sw := _font().get_string_size(score_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
		_text(score_txt, Vector2(x + cw - 28 - sw, y + 74), 36, Color(0.02, 0.55, 0.8))
	draw_set_transform(Vector2.ZERO)

# --- Archivos (importar, carpeta y exportar) ---------------------------------------

func _files_half() -> float:
	return (viewport_size.x - 110.0 - 80.0 - 40.0) / 2.0

func _files_tap(pos: Vector2) -> void:
	pos.y -= top_inset
	var x := 55.0
	var cw := viewport_size.x - 110.0
	var half := _files_half()
	if Rect2(x + 40, 370, cw - 80, 100).has_point(pos):
		file_dialog.popup_centered_ratio(0.85)
	elif Rect2(x + 40, 810, half, 100).has_point(pos):
		folder_dialog.popup_centered_ratio(0.85)
	elif Rect2(x + 80 + half, 810, half, 100).has_point(pos):
		_sync_folder()
	elif Rect2(x + 40, 1200, cw - 80, 100).has_point(pos):
		_export_library()

func _draw_files() -> void:
	var w := viewport_size.x
	var x := 55.0
	var cw := w - 110.0
	var muted := Color(0.62, 0.75, 0.88)
	var panel_col := Color(0.08, 0.13, 0.22, 0.92)
	var accent := Color(0.02, 0.68, 0.88)
	var half := _files_half()
	draw_set_transform(Vector2(0, top_inset))
	_text("ARCHIVOS", Vector2(55, 105), 58, Color.WHITE)
	_panel(Rect2(x, 200, cw, 300), panel_col, 34)
	_text("Importar mapa", Vector2(x + 40, 285), 40, Color.WHITE)
	_text("Elige un archivo .osz de osu! de tu móvil.", Vector2(x + 40, 335), 26, muted)
	_button(Rect2(x + 40, 370, cw - 80, 100), "Importar .osz", accent)
	_panel(Rect2(x, 540, cw, 420), panel_col, 34)
	_text("Carpeta de canciones", Vector2(x + 40, 625), 40, Color.WHITE)
	var shown_dir := library_dir if library_dir != "" else "Sin configurar (por defecto: Documentos/TilesFOSS)"
	_text(_fit(shown_dir, cw - 80, 24), Vector2(x + 40, 675), 24, Color(0.5, 0.95, 0.75) if library_dir != "" else muted)
	_text(_fit("Deja tus .osz en \"Por importar\" y pulsa Recargar.", cw - 80, 24), Vector2(x + 40, 720), 24, muted)
	_text(_fit("Al reinstalar la app, Recargar restaura lo de \"Importadas\".", cw - 80, 24), Vector2(x + 40, 760), 24, muted)
	_button(Rect2(x + 40, 810, half, 100), "Elegir carpeta", Color(0.14, 0.22, 0.34))
	_button(Rect2(x + 80 + half, 810, half, 100), "Recargando..." if syncing else "Recargar mapas", accent)
	_panel(Rect2(x, 1000, cw, 330), panel_col, 34)
	_text("Exportar canciones", Vector2(x + 40, 1085), 40, Color.WHITE)
	var n_songs := 0
	for g in groups:
		if g.id != "demo":
			n_songs += 1
	_text(_fit("Guarda un .osz de cada canción en \"Importadas\" (%d en la biblioteca)." % n_songs, cw - 80, 24), Vector2(x + 40, 1135), 24, muted)
	_text(_fit("Así no las pierdes si desinstalas la app.", cw - 80, 24), Vector2(x + 40, 1175), 24, muted)
	_button(Rect2(x + 40, 1200, cw - 80, 100), "Exportando..." if syncing else "Exportar canciones", accent)
	_text(_fit("Récords, listas y favoritas se guardan en %s dentro de la carpeta." % PROGRESS_FILE, cw, 22), Vector2(55, 1375), 22, muted)
	_text(_fit("Los mapas importados antes de los fondos hay que importarlos otra vez.", cw, 22), Vector2(55, 1415), 22, muted)
	if status_time > 0.0:
		_text(_fit(status_text, cw, 26), Vector2(55, 1460), 26, Color(1, 0.45, 0.45) if status_error else Color(0.5, 0.95, 0.75))
	draw_set_transform(Vector2.ZERO)

# --- Música ----------------------------------------------------------------------

## Una tarjeta de canción. kind: song (corazón), remove (quitar de lista), playlist, plain.
func _draw_card(g: Dictionary, x: float, y: float, w: float, kind: String) -> void:
	_panel(Rect2(x, y, w, CARD_H), Color(0.97, 0.98, 1), 28)
	var ink := Color(0.12, 0.22, 0.31)
	var soft := Color(0.42, 0.52, 0.62)
	var text_w := w - 190 - 150
	if kind == "playlist":
		draw_rect(Rect2(x, y, 190, CARD_H), Color(0.45, 0.4, 0.95))
		_draw_nav_icon(1, Vector2(x + 95, y + CARD_H / 2.0), 34.0, Color.WHITE)
		_text(_fit(g.title, text_w, 38), Vector2(x + 215, y + 82), 38, ink)
		_text(_fit(g.artist, text_w, 27), Vector2(x + 215, y + 132), 27, soft)
		var cc := Vector2(x + w - 60, y + CARD_H / 2.0)
		draw_polyline(PackedVector2Array([cc + Vector2(-8, -22), cc + Vector2(12, 0), cc + Vector2(-8, 22)]), Color(0.7, 0.78, 0.88), 7.0)
		return
	var first: Dictionary = g.entries[0]
	var count: int = g.entries.size()
	var thumb: Texture2D = _group_thumb(g) if show_thumbs else null
	if thumb != null:
		_draw_cover(thumb, Rect2(x, y, 190, CARD_H))
		if count > 1:
			draw_rect(Rect2(x, y + CARD_H - 46, 190, 46), Color(0, 0, 0, 0.55))
			_text_centered("%d dif." % count, x + 95, y + CARD_H - 13, 28, Color.WHITE)
	else:
		draw_rect(Rect2(x, y, 190, CARD_H), _badge_color(first))
		if count > 1:
			_text_centered(first.badge, x + 95, y + CARD_H / 2 - 2, 44, Color.WHITE)
			_text_centered("%d dif." % count, x + 95, y + CARD_H / 2 + 44, 28, Color(1, 1, 1, 0.9))
		else:
			_text_centered(first.badge, x + 95, y + CARD_H / 2 + 15, 44, Color.WHITE)
	_text(_fit(g.title, text_w, 38), Vector2(x + 215, y + 82), 38, ink)
	var sub: String = ("%s · %d dificultades" % [g.artist, count]) if count > 1 else ("%s · %s" % [g.artist, first.version])
	_text(_fit(sub, text_w, 27), Vector2(x + 215, y + 132), 27, soft)
	if kind == "song":
		_draw_heart(Vector2(x + w - 66, y + CARD_H / 2 - 8), 36.0, Color(1.0, 0.28, 0.4) if favorites.has(g.id) else Color(0.8, 0.85, 0.91))
	elif kind == "remove":
		var c := Vector2(x + w - 66, y + CARD_H / 2.0)
		draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), Color(0.85, 0.45, 0.5), 8.0)
		draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), Color(0.85, 0.45, 0.5), 8.0)
	else:
		var pc := Vector2(x + w - 62, y + CARD_H / 2.0)
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-14, -22), pc + Vector2(-14, 22), pc + Vector2(22, 0)]), Color(0.04, 0.65, 0.88))

func _draw_music() -> void:
	var muted := Color(0.62, 0.75, 0.88)
	var x := 55.0
	var w := viewport_size.x - 110.0
	for i in view_groups.size():
		var g: Dictionary = view_groups[i]
		var y := LIST_TOP + i * (CARD_H + CARD_GAP) - scroll_y
		if y + CARD_H < LIST_TOP - 30.0 or y > viewport_size.y:
			continue
		var kind := "song"
		if g.has("playlist_idx"):
			kind = "playlist"
		elif g.get("in_playlist", false):
			kind = "remove"
		_draw_card(g, x, y, w, kind)
	if view_groups.is_empty():
		var empty_msg := "Sin resultados para \"%s\"" % search_query
		if search_query.strip_edges() == "":
			if music_tab == 1:
				empty_msg = "Aún no tienes favoritas: toca el corazón de una canción."
			elif music_tab == 2:
				empty_msg = "Aún no tienes listas: crea una con \"+ Nueva lista\"." if open_playlist < 0 else "Esta lista está vacía: usa \"+ Lista\" al abrir una canción."
		_text(_fit(empty_msg, w, 30), Vector2(x, LIST_TOP + 70), 30, muted)
	elif music_tab == 0 and groups.size() == 1 and not search_open:
		_text("Importa un mapa de osu! (.osz) en la pestaña Archivos.", Vector2(x, LIST_TOP + CARD_H + CARD_GAP + 70.0 - scroll_y), 28, muted)
	# La cabecera tapa las tarjetas que suben por debajo.
	_background_rect(Rect2(0, 0, viewport_size.x, LIST_TOP - 22))
	draw_set_transform(Vector2(0, top_inset))
	var title := "MÚSICA"
	if music_tab == 2 and open_playlist >= 0 and open_playlist < playlists.size():
		title = String(playlists[open_playlist].name)
	_text(_fit(title, viewport_size.x - 380, 58), Vector2(55, 105), 58, Color.WHITE)
	var dark := Color(0.14, 0.22, 0.34)
	if search_open:
		_button(Rect2(viewport_size.x - 300, 150, 245, 95), "Cerrar", Color(0.17, 0.25, 0.37))
	else:
		_button(Rect2(viewport_size.x - 300, 40, 245, 80), "Buscar", dark)
		_button(Rect2(55, 150, 130, 95), "Todas", Color(0.04, 0.65, 0.88) if music_tab == 0 else dark)
		_button(Rect2(195, 150, 205, 95), "Favoritas", Color(0.9, 0.25, 0.4) if music_tab == 1 else dark)
		_button(Rect2(410, 150, 160, 95), "Listas", Color(0.45, 0.4, 0.95) if music_tab == 2 else dark)
		if music_tab != 2:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), "Orden: %s" % SORT_MODES[sort_mode], dark)
		elif open_playlist < 0:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), "+ Nueva lista", Color(0.04, 0.65, 0.88))
		else:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), "¿Seguro?" if delete_armed else "Eliminar lista", Color(0.78, 0.2, 0.3) if delete_armed else dark)
	draw_set_transform(Vector2.ZERO)
	if status_time > 0.0:
		_text(_fit(status_text, viewport_size.x - 110, 26), Vector2(55, 272 + top_inset), 26, Color(1, 0.45, 0.45) if status_error else Color(0.5, 0.95, 0.75))

func _draw_library() -> void:
	thumb_budget = 2
	_background()
	if tab == TAB_HOME:
		_draw_home()
	elif tab == TAB_FILES:
		_draw_files()
	else:
		_draw_music()
	_draw_nav()
	if not open_group.is_empty():
		_draw_difficulty_picker()


## Construye el chart jugable de un mapa parseado con el nivel de dificultad actual.
## Devuelve {} si no queda ninguna nota.
func _build_from_parsed(parsed: Dictionary) -> Dictionary:
	var lvl: Dictionary = DIFFICULTY_LEVELS[diff_level]
	var playable: Array = OsuImporter.build_chart(parsed, OsuImporter.DEFAULT_MAX_FINGERS, float(lvl.event), float(lvl.lane))
	if playable.is_empty():
		return {}
	var out_chart: Array = [{"time": START_TIME, "lane": 0, "type": "start"}]
	out_chart.append_array(playable)
	var last_end := 0.0
	for n in playable:
		last_end = maxf(last_end, float(n.time) + float(n.get("duration", 0.0)))
	return {
		"chart": out_chart, "first": float(playable[0].time),
		"auto": OsuImporter.suggest_speed(playable, float(lvl.event)),
		"end": last_end + 1.06, "total": parsed.objects.size(),
		"dropped": parsed.objects.size() - playable.size(),
	}

## Reconstruye el chart de la canción abierta (al cambiar la dificultad en "preparar").
func _rebuild_chart() -> bool:
	if current_parsed.is_empty():
		return false
	var built := _build_from_parsed(current_parsed)
	if built.is_empty():
		return false
	chart = built.chart; chart_end = built.end; first_note_time = built.first; auto_mult = built.auto
	var note_count := 0
	var hold_count := 0
	for n in chart:
		if n.type == "start": continue
		note_count += 1
		if n.type == "hold": hold_count += 1
	song_stats.notes = note_count
	song_stats.holds = hold_count
	song_stats.dropped = built.dropped
	song_stats.total = built.total
	if audio_stream == null or audio_stream.get_length() <= 0.0:
		song_stats.duration = chart_end - 1.06
	return true

func _adjust_diff(delta: int) -> void:
	if current_parsed.is_empty():
		return
	var old := diff_level
	diff_level = clampi(diff_level + delta, 0, DIFFICULTY_LEVELS.size() - 1)
	if diff_level == old:
		return
	if not _rebuild_chart():
		diff_level = old
		return
	_save_settings()

func _select_song(entry: Dictionary) -> void:
	_stop_audio()
	var new_chart: Array = []
	var stream: AudioStream = null
	var new_lead := false
	var new_first := 0.0
	var new_auto := 1.0
	var new_end := 12.4
	var dropped := 0
	var total := 0
	var new_parsed: Dictionary = {}
	if entry.demo:
		new_chart = demo_chart
	else:
		var parsed: Dictionary = OsuImporter.parse_osu(FileAccess.get_file_as_string(entry.osu_path))
		if not parsed.ok:
			_show_status(parsed.error, true)
			return
		var built := _build_from_parsed(parsed)
		if built.is_empty():
			_show_status("No quedaron notas jugables en este mapa", true)
			return
		new_chart = built.chart
		new_lead = true
		new_first = built.first
		new_auto = built.auto
		total = built.total
		dropped = built.dropped
		new_end = built.end
		new_parsed = parsed
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
	audio_stream = stream; current_song = entry; current_parsed = new_parsed
	_reload_bg()
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
	speed_auto = cfg.get_value("speed", "auto", false)
	speed_mult = clampf(float(cfg.get_value("speed", "mult", 3.0)), SPEED_MIN, SPEED_MAX)
	lives_mode = bool(cfg.get_value("mods", "lives_mode", false))
	infinite_mode = bool(cfg.get_value("mods", "infinite", false))
	diff_level = clampi(int(cfg.get_value("mods", "diff", 1)), 0, DIFFICULTY_LEVELS.size() - 1)
	library_dir = String(cfg.get_value("library", "dir", ""))
	lives_setting = clampi(int(cfg.get_value("mods", "lives", 3)), LIVES_MIN, LIVES_MAX)
	show_thumbs = bool(cfg.get_value("display", "show_thumbs", true))
	var fav_list = cfg.get_value("library", "favorites", [])
	if fav_list is Array:
		for fid in fav_list:
			favorites[String(fid)] = true
	sort_mode = clampi(int(cfg.get_value("library", "sort", 0)), 0, SORT_MODES.size() - 1)
	last_played = {"id": String(cfg.get_value("library", "last_id", "")), "version": String(cfg.get_value("library", "last_version", ""))}
	var pl = cfg.get_value("library", "playlists", [])
	if pl is Array:
		for p in pl:
			if p is Dictionary and p.has("name") and p.get("refs") is Array:
				playlists.append({"name": String(p.name), "refs": (p.refs as Array).duplicate()})
	show_bg = bool(cfg.get_value("display", "show_bg", true))
	bg_vis = clampf(float(cfg.get_value("display", "bg_vis", 0.30)), 0.1, 0.7)
	if cfg.has_section("best"):
		for key in cfg.get_section_keys("best"):
			var v = cfg.get_value("best", key)
			if v is Dictionary:
				bests[key] = v

func _save_settings() -> void:
	home_dirty = true
	var cfg := ConfigFile.new()
	cfg.set_value("speed", "auto", speed_auto)
	cfg.set_value("speed", "mult", speed_mult)
	cfg.set_value("mods", "lives_mode", lives_mode)
	cfg.set_value("mods", "infinite", infinite_mode)
	cfg.set_value("mods", "diff", diff_level)
	cfg.set_value("library", "dir", library_dir)
	cfg.set_value("mods", "lives", lives_setting)
	cfg.set_value("display", "show_thumbs", show_thumbs)
	cfg.set_value("library", "favorites", favorites.keys())
	cfg.set_value("library", "sort", sort_mode)
	cfg.set_value("library", "last_id", String(last_played.get("id", "")))
	cfg.set_value("library", "last_version", String(last_played.get("version", "")))
	cfg.set_value("library", "playlists", playlists)
	cfg.set_value("display", "show_bg", show_bg)
	cfg.set_value("display", "bg_vis", bg_vis)
	for key in bests:
		cfg.set_value("best", key, bests[key])
	cfg.save(SETTINGS_PATH)
	_save_progress_file()

# --- Puntaje y rangos ----------------------------------------------------

func _reload_bg() -> void:
	bg_texture = null
	if show_bg and not current_song.is_empty():
		bg_texture = OsuImporter.load_image(String(current_song.get("bg_path", "")))

func _adjust_bg(delta: float) -> void:
	bg_vis = snappedf(clampf(bg_vis + delta, 0.1, 0.7), 0.05)
	_save_settings()

func _song_key(entry: Dictionary) -> String:
	var key := "%s|%s" % [entry.get("set_id", "demo"), entry.get("version", "")]
	if not entry.get("demo", false) and diff_level != 1:
		key += "|d%d" % diff_level   # cada nivel de dificultad de notas tiene sus propios récords
	return key

## Precisión 0..100: Perfect 100 %, Great 80 %, Good 50 %, cada VACÍO resta 25 % de una nota.
func _accuracy() -> float:
	var total: int = maxi(1, int(song_stats.notes))
	var pts := perfects * 100.0 + greats * 80.0 + goods * 50.0 - empties * 25.0
	return clampf(pts / (total * 100.0) * 100.0, 0.0, 100.0)

func _rank_for(acc: float, miss_count: int) -> int:
	if acc >= 98.0 and miss_count == 0: return 5   # SS
	if acc >= 95.0: return 4                       # S
	if acc >= 90.0: return 3                       # A
	if acc >= 80.0: return 2                       # B
	if acc >= 70.0: return 1                       # C
	return 0                                       # D

func _finish_run() -> void:
	if infinite_run:
		_finish_infinite()
		return
	run_accuracy = _accuracy()
	run_rank = _rank_for(run_accuracy, misses + empties)
	run_mult = _lives_mult(run_lives) if run_lives > 0 else 1.0
	if run_lives > 0:
		score = roundi(score * run_mult)
	if failed or run_lives <= 0:   # solo el modo Vidas guarda récords
		run_record = false
		return
	var key := _song_key(current_song)
	var old: Dictionary = bests.get(key, {})
	run_record = score > int(old.get("score", 0))
	if run_record or old.is_empty():
		bests[key] = {"score": score, "rank": maxi(run_rank, int(old.get("rank", 0))), "acc": run_accuracy}
	elif run_rank > int(old.get("rank", 0)):
		old["rank"] = run_rank
		bests[key] = old
	_save_settings()

func _text_centered(value: String, center_x: float, y: float, size: int, color: Color) -> void:
	var width := _font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(center_x - width / 2, y), size, color)

# --- Pausa / audio -------------------------------------------------------

func _set_paused(value: bool) -> void:
	paused = value
	player.stream_paused = value

func _stop_audio() -> void:
	previewing = false
	player.stop()
	player.stream_paused = false
	audio_started = false

## Escuchar solo el audio de la canción abierta (sin jugar).
func _toggle_preview() -> void:
	if previewing:
		_stop_audio()
		return
	if audio_stream == null:
		return
	player.stream = audio_stream
	player.pitch_scale = 1.0
	player.stream_paused = false
	player.play()
	previewing = true

func _go_library() -> void:
	if infinite_run and screen == Screen.GAME and not finished:
		_store_infinite_best()
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
	elif screen == Screen.SETTINGS: _draw_settings()
	else: _draw_results()
	draw_set_transform(Vector2.ZERO)
	if overlay != "" and (screen == Screen.LIBRARY or screen == Screen.PREPARE):
		_draw_overlay()

func _draw_game() -> void:
	var lane_w := viewport_size.x / LANES
	# Fondo base: azul claro; con las 3 estrellas pasa a un verde menta suave (y se queda en las coronas).
	var base_col := Color(0.74, 0.88, 0.98).lerp(Color(0.78, 0.92, 0.82), bg_blend)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), base_col)
	if show_bg and bg_texture != null:
		_draw_cover(bg_texture, Rect2(Vector2.ZERO, viewport_size))
		base_col.a = 1.0 - bg_vis   # misma capa de transparencia que ya tenía, con el color nuevo
		draw_rect(Rect2(Vector2.ZERO, viewport_size), base_col)
	for lane in LANES:
		draw_rect(Rect2(lane * lane_w, 0, lane_w, viewport_size.y), Color(0.9,0.96,1,0.20))
		draw_line(Vector2(lane * lane_w,0), Vector2(lane * lane_w,viewport_size.y), Color.WHITE, 3)
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > ahead: break
		if note.done and note.get("released", false):
			var gb: float = hit_y + (song_time - float(note.release_time)) * speed
			var gh: float = maxf(0.0, (float(note.time) + float(note.duration) - float(note.release_time)) * speed)
			draw_rect(Rect2(note.lane * lane_w + 2, gb - gh, lane_w - 4, gh), Color(0.42, 0.47, 0.55, 0.32))
			continue
		if note.done or (note.type == "start" and started): continue
		var bottom: float = viewport_size.y if note.type == "start" and not started else hit_y - (note.time - song_time) * speed
		var height: float = note.height
		if note.type == "hold":
			if note.holding:
				var remaining: float = max(0.0, note.time + note.duration - song_time)
				height = max(90.0, remaining * speed)
				bottom = hit_y
			else:
				height = maxf(120.0, note.duration * speed)
		var rect := Rect2(note.lane * lane_w + 2, bottom - height, lane_w - 4, height)
		if note.type == "hold":
			# Misma silueta cayendo y sosteniendo: solo cambia la intensidad.
			draw_rect(rect, Color(0.01, 0.035, 0.06) if not note.holding else Color(0.0, 0.07, 0.11))
			_draw_hold_marks(rect, note.holding)
		else:
			draw_rect(rect, Color(0.01,0.01,0.015))
		if resume_pending and i in resume_idxs and not note.holding:
			draw_rect(rect, Color.WHITE, false, 6.0)
			_text("Continuar", Vector2(rect.position.x + 18, rect.get_center().y + 12), 35, Color.WHITE)
		if note.type == "start": _text("Comenzar", Vector2(rect.position.x+18,rect.get_center().y+12), 35, Color.WHITE)
	for effect in effects:
		var progress: float = 1.0 - float(effect.time) / float(effect.duration)
		var color: Color = effect.color; color.a *= 1.0 - progress
		var center := Vector2((float(effect.lane)+0.5)*lane_w, float(effect.y))
		var half := Vector2(lane_w*(0.20+progress*0.24), 28.0+progress*38.0)
		draw_rect(Rect2(center-half, half*2.0), color, false, 7.0)
	if judgement_time > 0.0:
		var t := clampf(judgement_time / judgement_total, 0.0, 1.0)   # 1 al aparecer, 0 al irse
		var age := 1.0 - t
		var pop := 1.0 + 0.45 * maxf(0.0, 1.0 - age / 0.2)            # rebote al aparecer
		var fade := clampf(t / 0.3, 0.0, 1.0)
		var jcol := _judgement_color(last_judgement); jcol.a = fade
		_text_outlined(last_judgement, viewport_size.x / 2, 480 + top_inset - age * 40.0, int(68 * pop), jcol, Color(0.02, 0.05, 0.12, 0.95 * fade), 14)
	if combo >= 2:
		var ccol := Color.WHITE
		if combo >= 100: ccol = Color(1.0, 0.55, 0.85)
		elif combo >= 50: ccol = Color(1.0, 0.82, 0.2)
		elif combo >= 25: ccol = Color(0.55, 0.95, 1.0)
		var csize := int(100 + 40 * clampf(combo_pop / 0.18, 0.0, 1.0))
		_text_outlined(str(combo), viewport_size.x / 2, 200 + top_inset, csize, ccol, Color(0.04, 0.16, 0.32, 0.95), 16)
		_text_outlined("COMBO", viewport_size.x / 2, 255 + top_inset, 30, Color.WHITE, Color(0.04, 0.16, 0.32, 0.95), 8)
	_button(Rect2(viewport_size.x-145,35+top_inset,110,100), "II", Color(0.06,0.12,0.2,0.72))
	if run_lives == LIVES_MIN:
		_draw_lives_bars(55, 60 + top_inset, 64, 16, 12)
	elif run_lives > LIVES_MIN:
		_text_outlined(str(lives_left), 90, 105 + top_inset, 60, Color(1.0, 0.3, 0.4), Color(0.04, 0.16, 0.32, 0.95), 10)
	if infinite_run:
		var ltxt := "Vuelta %d · x%.1f" % [lap, lap_factor]
		var lw := _font().get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_text_outlined(ltxt, 55 + lw / 2.0, 150 + top_inset, 30, Color.WHITE, Color(0.04, 0.16, 0.32, 0.95), 8)
		for i in stars:
			_draw_award("star", Vector2(68 + i * 38, 190 + top_inset), 14.0, true)
		for i in crowns:
			_draw_award("crown", Vector2(68 + i * 38, 232 + top_inset), 14.0, true)
		if banner_time > 0.0:
			# Solo los iconos: tantas estrellas/coronas como lleves (1, 2 o 3), sin texto.
			var n_icons := stars if banner_kind == "star" else crowns
			var pop := 60.0 * (1.0 + 0.2 * clampf(banner_time - 1.5, 0.0, 0.3) / 0.3)
			for i in n_icons:
				var ix := viewport_size.x / 2.0 + (i - (n_icons - 1) / 2.0) * 150.0
				_draw_award(banner_kind, Vector2(ix, 640 + top_inset), pop, true)
		if lap_banner_time > 0.0:
			var lt := clampf(lap_banner_time / 0.5, 0.0, 1.0)
			_text_outlined(lap_banner_text, viewport_size.x / 2, 960 + top_inset, 72, Color(0.75, 0.6, 1.0, lt), Color(0.02, 0.05, 0.12, 0.95 * lt), 14)
	var prog := clampf(song_time / maxf(0.1, chart_end), 0.0, 1.0)
	draw_rect(Rect2(0, top_inset, viewport_size.x, 10), Color(0.04, 0.16, 0.32, 0.45))
	draw_rect(Rect2(0, top_inset, viewport_size.x * prog, 10), Color(0.02, 0.68, 0.88))
	if failed and finished:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.6))
		_text_outlined(fail_text, viewport_size.x / 2, viewport_size.y / 2, 90, Color(1.0, 0.3, 0.35), Color(0.02, 0.05, 0.12, 0.95), 14)
	if life_menu:
		var lk := 0.45 if life_menu_lock > 0.0 else 1.0
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.74))
		draw_set_transform(Vector2(0, ui_off))
		_text_outlined("PERDISTE UNA VIDA", viewport_size.x / 2, 520, 62, Color(1.0, 0.3, 0.35), Color(0.02, 0.05, 0.12, 0.95), 12)
		if run_lives == LIVES_MIN:
			_draw_lives_bars(viewport_size.x / 2 - 249.0, 590, 150, 30, 24)
			_text_centered("Te quedan %d" % lives_left if lives_left > 0 else "¡Última oportunidad!", viewport_size.x / 2, 700, 34, Color(0.82, 0.91, 1))
		else:
			_text_outlined(str(lives_left), viewport_size.x / 2, 680, 150, Color(1.0, 0.3, 0.4), Color(0.02, 0.05, 0.12, 0.95), 14)
			_text_centered("vidas restantes" if lives_left > 0 else "¡Última oportunidad!", viewport_size.x / 2, 735, 30, Color(0.82, 0.91, 1))
		_button(Rect2(170, 760, viewport_size.x - 340, 135), "RENDIRSE", Color(0.62, 0.16, 0.22, lk))
		_button(Rect2(170, 930, viewport_size.x - 340, 135), "CONTINUAR", Color(0.02, 0.68, 0.88, lk))
		draw_set_transform(Vector2.ZERO)
	elif paused and not resume_pending:
		draw_rect(Rect2(Vector2.ZERO,viewport_size), Color(0,0,0,0.74))
		draw_set_transform(Vector2(0, ui_off))
		_text("PAUSA", Vector2(viewport_size.x/2-110,600), 62, Color.WHITE)
		_button(Rect2(170,760,viewport_size.x-340,135), "CONTINUAR", Color(0.02,0.68,0.88))
		_button(Rect2(170,930,viewport_size.x-340,135), "SALIR", Color(0.22,0.28,0.38))
		draw_set_transform(Vector2.ZERO)

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
		var bcol := Color(0.45, 0.52, 0.62)
		var pb: Dictionary = bests.get(_song_key(e), {})
		if not pb.is_empty():
			bcol = RANK_COLORS[int(pb.rank)]
		elif bests.has(_song_key(e) + "|inf"):
			bcol = Color(0.5, 0.38, 0.92)
		_panel(Rect2(r.position.x, r.position.y, 130, r.size.y), bcol, 24)
		var row_best: Dictionary = bests.get(_song_key(e), {})
		var inf_best: Dictionary = bests.get(_song_key(e) + "|inf", {})
		var n_crowns := int(inf_best.get("crowns", 0))
		var n_stars := int(inf_best.get("stars", 0))
		var has_icons := n_crowns > 0 or n_stars > 0
		var letter := "–" if row_best.is_empty() else String(RANKS[int(row_best.rank)])
		var lsize := int(clampf(r.size.y * 0.42, 30.0, 56.0)) if has_icons else 56
		var ly := r.position.y + r.size.y * 0.46 if has_icons else r.get_center().y + 16.0
		_text_centered(letter, r.position.x + 65, ly + lsize * 0.3, lsize, Color(1, 1, 1, 0.6) if row_best.is_empty() else Color.WHITE)
		if has_icons:
			var kind := "crown" if n_crowns > 0 else "star"
			var cnt := n_crowns if n_crowns > 0 else n_stars
			var ir := clampf(r.size.y * 0.13, 9.0, 16.0)
			for k in cnt:
				_draw_award(kind, Vector2(r.position.x + 65 + (k - (cnt - 1) / 2.0) * (ir * 2.6), r.position.y + r.size.y * 0.80), ir, true)
		_text(_fit(e.version, r.size.x - 180.0, 34), Vector2(r.position.x + 155, r.get_center().y + 12), 34, Color(0.12, 0.22, 0.31))

func _draw_prepare() -> void:
	_background(); draw_set_transform(Vector2(0, ui_off)); _button(Rect2(35,45,180,95),"< Volver",Color(0.14,0.22,0.34))
	var w := viewport_size.x
	var muted := Color(0.62, 0.75, 0.88)
	var prev_col := Color(0.78, 0.2, 0.3) if previewing else Color(0.02, 0.68, 0.88)
	if audio_stream == null:
		prev_col = Color(0.14, 0.22, 0.34, 0.4)
	_button(Rect2(w - 365, 45, 330, 95), "Detener" if previewing else "Escuchar", prev_col)
	_button(Rect2(235, 45, w - 620, 95), "+ A lista", Color(0.45, 0.4, 0.95))
	var text_w := w - 160
	_text(_fit(current_song.title, text_w, 58), Vector2(80,370), 58, Color.WHITE)
	_text(_fit("%s · %s" % [current_song.artist, current_song.version], text_w, 32), Vector2(82,445), 32, Color(0.68,0.84,0.96))
	_panel(Rect2(80,560,w-160,200),Color(0.08,0.13,0.22,0.92),34)
	_text("%d notas · %d sostenidas" % [song_stats.notes, song_stats.holds], Vector2(140,645), 38, Color.WHITE)
	_text("%s · %s" % [_format_time(song_stats.duration), "Con audio" if audio_stream != null else "Sin audio"], Vector2(140,715), 38, Color.WHITE if audio_stream != null else Color(1,0.6,0.6))
	# Dificultad de notas
	var cx := w / 2
	var lvl: Dictionary = DIFFICULTY_LEVELS[diff_level]
	var demo_song: bool = current_parsed.is_empty()
	_button(Rect2(100,800,190,110),"-",Color(0.14,0.22,0.34, 0.4 if demo_song else 1.0))
	_button(Rect2(w-290,800,190,110),"+",Color(0.14,0.22,0.34, 0.4 if demo_song else 1.0))
	_text_centered("Dificultad de notas", cx, 842, 28, muted)
	_text_centered("—" if demo_song else String(lvl.name), cx, 902, 52, Color(1, 1, 1, 0.4) if demo_song else lvl.color)
	# Velocidad
	_button(Rect2(100,950,190,120),"-",Color(0.14,0.22,0.34))
	_button(Rect2(w-290,950,190,120),"+",Color(0.14,0.22,0.34))
	_text_centered("Velocidad · AUTO" if speed_auto else "Velocidad · MANUAL (toca: auto)", cx, 992, 28, muted)
	_text_centered("x%.1f" % _effective_mult(), cx, 1052, 56, Color(0.3,0.9,1.0) if speed_auto else Color.WHITE)
	# Modificadores
	_panel(Rect2(80,1110,w-160,470),Color(0.08,0.13,0.22,0.92),34)
	_text("MODO", Vector2(130,1165), 28, muted)
	_button(_mode_rect(0), "CASUAL", Color(0.02,0.68,0.88) if not lives_mode else Color(0.17,0.25,0.37))
	_button(_mode_rect(1), "VIDAS", Color(0.78,0.2,0.3) if lives_mode and not infinite_mode else Color(0.17,0.25,0.37))
	_button(_mode_rect(2), "INFINITO", Color(0.5,0.38,0.92) if infinite_mode else Color(0.17,0.25,0.37))
	if lives_mode:
		_button(Rect2(130,1340,170,100), "-", Color(0.14,0.22,0.34))
		_button(Rect2(w-300,1340,170,100), "+", Color(0.14,0.22,0.34))
		_text_centered("%d vidas" % lives_setting, cx, 1405, 48, Color.WHITE)
		var m := _lives_mult(lives_setting)
		var pen_text := "Sin penalización de puntos" if lives_setting == LIVES_MIN else "Puntos x%.2f (-%d %%)" % [m, roundi((1.0 - m) * 100.0)]
		var pen_col := Color(0.5, 0.95, 0.75) if lives_setting == LIVES_MIN else Color(1.0, 0.75, 0.4)
		if infinite_mode:
			_text_centered("3 estrellas en la vuelta 1 y 3 coronas en las vueltas 2 y 3", cx, 1470, 24, Color(1.0, 0.82, 0.3))
			_text_centered("Cada vuelta acelera notas y canción: x1.0, x1.5, x2.0...", cx, 1500, 24, Color(1.0, 0.82, 0.3))
			_text_centered(pen_text, cx, 1532, 26, pen_col)
			_text_centered("Puedes fallar %d veces y seguir; el siguiente fallo termina." % lives_setting, cx, 1560, 22, muted)
		else:
			_text_centered(pen_text, cx, 1490, 28, pen_col)
			_text_centered("Puedes fallar %d veces y seguir; el siguiente fallo termina." % lives_setting, cx, 1545, 24, muted)
	else:
		_text_centered("Sin límite de fallos", cx, 1405, 40, Color.WHITE)
		_text_centered("Juega tranquilo: fallar solo rompe el combo. No se guarda.", cx, 1465, 28, muted)
	_draw_prepare_record(cx)
	_button(Rect2(100,1640,w-200,145),"JUGAR",Color(0.02,0.68,0.88))

## Mejor récord de esta canción para el modo elegido (Casual no guarda).
func _draw_prepare_record(cx: float) -> void:
	if not lives_mode:
		return
	var key := _song_key(current_song)
	var muted := Color(0.62, 0.75, 0.88)
	var gold := Color(1.0, 0.82, 0.3)
	if infinite_mode:
		var b: Dictionary = bests.get(key + "|inf", {})
		if b.is_empty():
			_text_centered("Récord: sin récord todavía", cx, 1620, 28, muted)
			return
		var n_st := mini(int(b.get("stars", 0)), 3)
		var n_cr := mini(int(b.get("crowns", 0)), 3)
		var label := "Vuelta %d · %d pts" % [int(b.get("laps", 1)), int(b.get("score", 0))]
		var ir := 15.0
		var step := ir * 2.7
		var icons_w := (n_st + n_cr) * step
		var text_w := _font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		var x := cx - (icons_w + (24.0 if icons_w > 0.0 else 0.0) + text_w) / 2.0
		for i in n_st:
			_draw_award("star", Vector2(x + step / 2.0 + i * step, 1609), ir, true)
		for i in n_cr:
			_draw_award("crown", Vector2(x + step / 2.0 + (n_st + i) * step, 1609), ir, true)
		_text(label, Vector2(x + icons_w + (24.0 if icons_w > 0.0 else 0.0), 1620), 28, gold)
	else:
		var b2: Dictionary = bests.get(key, {})
		if b2.is_empty():
			_text_centered("Récord: sin récord todavía", cx, 1620, 28, muted)
		else:
			_text_centered("Récord: %s · %d pts" % [RANKS[int(b2.rank)], int(b2.score)], cx, 1620, 28, gold)

func _draw_settings() -> void:
	_background(); draw_set_transform(Vector2(0, ui_off))
	var w := viewport_size.x
	var muted := Color(0.62, 0.75, 0.88)
	_text("AJUSTES", Vector2(55, 105 + top_inset), 58, Color.WHITE)
	_panel(Rect2(80, 330, w - 160, 180), Color(0.08, 0.13, 0.22, 0.92), 34)
	_text("Fondos de los mapas", Vector2(130, 415), 40, Color.WHITE)
	_text("Imagen del mapa detrás de las teclas", Vector2(130, 465), 26, muted)
	_button(Rect2(w - 330, 375, 200, 90), "SÍ" if show_bg else "NO", Color(0.02, 0.68, 0.88) if show_bg else Color(0.22, 0.28, 0.38))
	var a := 1.0 if show_bg else 0.4
	_panel(Rect2(80, 540, w - 160, 300), Color(0.08, 0.13, 0.22, 0.92 * a), 34)
	_text("Visibilidad del fondo", Vector2(130, 625), 40, Color(1, 1, 1, a))
	_button(Rect2(130, 690, 170, 110), "-", Color(0.14, 0.22, 0.34, a))
	_button(Rect2(w - 300, 690, 170, 110), "+", Color(0.14, 0.22, 0.34, a))
	_text_centered("%d %%" % roundi(bg_vis * 100.0), w / 2, 765, 56, Color(1, 1, 1, a))
	_panel(Rect2(80, 870, w - 160, 180), Color(0.08, 0.13, 0.22, 0.92), 34)
	_text("Miniaturas de canciones", Vector2(130, 955), 40, Color.WHITE)
	_text("Imagen del mapa en cada canción de la lista", Vector2(130, 1005), 26, muted)
	_button(Rect2(w - 330, 915, 200, 90), "SÍ" if show_thumbs else "NO", Color(0.02, 0.68, 0.88) if show_thumbs else Color(0.22, 0.28, 0.38))
	_text("Las carpetas de canciones, importar y exportar", Vector2(80, 1130), 26, muted)
	_text("están ahora en la pestaña Archivos.", Vector2(80, 1170), 26, muted)
	if status_time > 0.0:
		_text(_fit(status_text, w - 160, 26), Vector2(80, 1240), 26, Color(1, 0.45, 0.45) if status_error else Color(0.5, 0.95, 0.75))
	_draw_nav()

func _draw_results_infinite() -> void:
	_background(); draw_set_transform(Vector2(0, ui_off)); _text_centered("MODO INFINITO", viewport_size.x / 2, 230, 58, Color.WHITE)
	var w := viewport_size.x
	_panel(Rect2(90, 300, w - 180, 1010), Color(0.96, 0.98, 1), 38)
	var dark := Color(0.12, 0.22, 0.32)
	var muted := Color(0.42, 0.52, 0.62)
	_text_centered("Llegaste a la vuelta", w / 2, 410, 32, muted)
	_text_centered(str(lap), w / 2, 590, 200, Color(0.5, 0.38, 0.92))
	_text_centered("velocidad x%.1f" % lap_factor, w / 2, 660, 34, dark)
	_text("Estrellas", Vector2(170, 760), 38, dark)
	_text("Coronas", Vector2(170, 880), 38, dark)
	for i in 3:
		_draw_award("star", Vector2(w - 170 - 270 + 45 + i * 90, 745), 34.0, i < stars)
		_draw_award("crown", Vector2(w - 170 - 270 + 45 + i * 90, 865), 34.0, i < crowns)
	if failed:
		_text_centered(fail_text, w / 2, 980, 32, Color(0.9, 0.2, 0.28))
	if run_record:
		_text_centered("¡Nuevo récord!", w / 2, 1030, 34, Color(1.0, 0.6, 0.1))
	if run_lives > 0:
		var pen_note := "%d vidas · sin penalización" % run_lives if run_lives == LIVES_MIN else "%d vidas · puntos x%.2f" % [run_lives, run_mult]
		_text_centered(pen_note, w / 2, 1085, 24, muted)
	_text("Puntuación", Vector2(170, 1120), 29, muted); _text(str(score), Vector2(170, 1200), 68, Color(0.02, 0.62, 0.86))
	var ib: Dictionary = bests.get(_song_key(current_song) + "|inf", {})
	if not ib.is_empty():
		_text_centered("Mejor: vuelta %d · %d pts" % [int(ib.get("laps", 1)), int(ib.get("score", 0))], w / 2, 1270, 28, muted)
	_button(Rect2(110, 1400, w - 220, 135), "REPETIR", Color(0.02, 0.68, 0.88)); _button(Rect2(110, 1570, w - 220, 120), "CANCIONES", Color(0.17, 0.25, 0.37))

func _draw_results() -> void:
	if infinite_run:
		_draw_results_infinite()
		return
	_background(); draw_set_transform(Vector2(0, ui_off)); _text_centered("RESULTADOS", viewport_size.x / 2, 230, 58, Color.WHITE)
	var w := viewport_size.x
	_panel(Rect2(90, 300, w - 180, 1010), Color(0.96, 0.98, 1), 38)
	var dark := Color(0.12, 0.22, 0.32)
	var muted := Color(0.42, 0.52, 0.62)
	# Rango grande
	var rcol: Color = RANK_COLORS[run_rank]
	_text_centered(RANKS[run_rank], w / 2, 560, 300, rcol)
	_text_centered("Precisión %.1f %%" % run_accuracy, w / 2, 640, 40, dark)
	if run_record:
		_text_centered("¡Nuevo récord!", w / 2, 700, 34, Color(1.0, 0.6, 0.1))
	if failed:
		_text_centered(fail_text, w / 2, 745, 32, Color(0.9, 0.2, 0.28))
	elif run_lives > 0:
		_text_centered("Modo Vidas · %d vidas · puntos x%.2f" % [run_lives, run_mult], w / 2, 745, 28, muted)
	else:
		_text_centered("Casual · esta partida no se guarda", w / 2, 745, 28, muted)
	_text("Puntuación", Vector2(170, 800), 29, muted); _text(str(score), Vector2(170, 880), 68, Color(0.02, 0.62, 0.86))
	_text("Perfect: %d" % perfects, Vector2(170, 980), 34, dark); _text("Great: %d" % greats, Vector2(w / 2 + 20, 980), 34, dark)
	_text("Good: %d" % goods, Vector2(170, 1045), 34, dark); _text("Fallos: %d" % misses, Vector2(w / 2 + 20, 1045), 34, dark)
	_text("Vacíos: %d" % empties, Vector2(170, 1110), 34, dark); _text("Combo máx: %d" % max_combo, Vector2(w / 2 + 20, 1110), 34, dark)
	var best: Dictionary = bests.get(_song_key(current_song), {})
	if run_lives > 0 and not best.is_empty():
		_text_centered("Mejor: %s · %d" % [RANKS[int(best.rank)], int(best.score)], w / 2, 1215, 32, muted)
	_button(Rect2(110, 1400, w - 220, 135), "REPETIR", Color(0.02, 0.68, 0.88)); _button(Rect2(110, 1570, w - 220, 120), "CANCIONES", Color(0.17, 0.25, 0.37))

## Mismo fondo que _background() pero solo dentro de un rectángulo (para tapar la lista bajo la cabecera).
func _background_rect(r: Rect2) -> void:
	draw_rect(r, Color(0.025, 0.05, 0.1))
	var rect_poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var center := Vector2(viewport_size.x * 0.75, viewport_size.y * 0.22)
	for i in range(10):
		var rad := 700.0 - i * 50.0
		var circle := PackedVector2Array()
		for k in 48:
			circle.append(center + Vector2(cos(k * TAU / 48.0), sin(k * TAU / 48.0)) * rad)
		for piece in Geometry2D.intersect_polygons(circle, rect_poly):
			draw_colored_polygon(piece, Color(0, 0.58, 0.95, 0.025))

func _background() -> void:
	draw_rect(Rect2(Vector2.ZERO,viewport_size),Color(0.025,0.05,0.1))
	if show_bg and bg_texture != null and (screen == Screen.PREPARE or screen == Screen.RESULTS):
		_draw_cover(bg_texture, Rect2(Vector2.ZERO, viewport_size))
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.025, 0.05, 0.1, 0.82))
	for i in range(10): draw_circle(Vector2(viewport_size.x*0.75,viewport_size.y*0.22),700-i*50,Color(0,0.58,0.95,0.025))

func _button(rect: Rect2, label: String, color: Color) -> void:
	_panel(rect,color,24); var width := _font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,34).x
	_text(label,Vector2(rect.get_center().x-width/2,rect.get_center().y+12),34,Color.WHITE)

func _panel(rect: Rect2, color: Color, radius: float) -> void: draw_style_box(_box(color,radius),rect)
func _box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color=color
	box.corner_radius_top_left=int(radius); box.corner_radius_top_right=int(radius); box.corner_radius_bottom_left=int(radius); box.corner_radius_bottom_right=int(radius)
	return box
func _text_outlined(value: String, center_x: float, y: float, size: int, color: Color, outline_color: Color, outline: int) -> void:
	var font := _font()
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos := Vector2(center_x - width / 2.0, y)
	draw_string_outline(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	draw_string(font, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Dibuja la textura rellenando el rectángulo (recorta lo que sobra, sin deformar).
func _draw_cover(tex: Texture2D, rect: Rect2, tint := Color.WHITE) -> void:
	var ts := tex.get_size()
	var k := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
	var src_size := rect.size / k
	draw_texture_rect_region(tex, rect, Rect2((ts - src_size) / 2.0, src_size), tint)

func _text(value: String, pos: Vector2, size: int, color: Color) -> void: draw_string(_font(),pos,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func _font() -> Font: return ThemeDB.fallback_font
