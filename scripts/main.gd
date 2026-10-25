extends Node2D

enum Screen { LIBRARY, PREPARE, GAME, RESULTS, SETTINGS, PALETTE }
const LANES := 4
const NORMAL_HEIGHT := 455.0
const BASE_SPEED := 760.0
const SETTINGS_PATH := "user://settings.cfg"
const SPEED_MIN := 0.5
const SPEED_MAX := 5.0
const SPEED_STEP := 0.1
const HIT_MARGIN := 340.0   # distancia de la línea de golpeo al borde inferior de la pantalla
const OsuImporter = preload("res://scripts/osu_importer.gd")
const TilesLang = preload("res://scripts/i18n.gd")
const TilesPalette = preload("res://scripts/palette.gd")
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
var sfx_on := true               # ajuste: efectos de sonido al perder
var sfx_player: AudioStreamPlayer = null
var sfx_fail: AudioStreamWAV = null
var sfx_life: AudioStreamWAV = null
var fade_tween: Tween = null
var amb_player: AudioStreamPlayer = null   # música de fondo suave al abrir la app
var amb_tween: Tween = null
var amb_player2: AudioStreamPlayer = null   # segundo canal: permite el fundido cruzado entre canciones
var amb_cur: AudioStreamPlayer = null
var amb_tweens := {}
var note_len := 1.0      # ajuste: largo de las notas normales (1.0 = el de siempre)
var amb_on := false
var amb_song := false   # el ambiente actual es la canción del mapa abierto en Preparar
var amb_retry := 0.0    # espera antes de volver a intentar arrancar la música de fondo
var amb_enabled := true  # ajuste: música de fondo en menús
var music_vol := 1.0     # ajuste: volumen de la música (0 - 1)
var sfx_vol := 1.0       # ajuste: volumen de los efectos (0 - 1)
var set_scroll := 0.0    # desplazamiento de Ajustes
var set_press_id := -999
var set_press_pos := Vector2.ZERO
var set_dragged := false
const SETTINGS_END := 2820.0   # fin del contenido de Ajustes (unidades de 1080 px)
var prep_tex: Texture2D = null   # imagen del mapa en Preparar
var input_y: Dictionary = {}   # altura (y) del dedo de cada toque, para dibujar la larga donde lo pones
var effects: Array = []
var marks: Array = []   # círculos rojos suaves donde tocaste en vacío
const MARK_TIME := 0.09
var input_x: Dictionary = {}
var dying: Array = []   # teclas recién tocadas que se deshacen desde el centro
const DIE_TIME := 0.04
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
var game_mode := 0           # 0 = Estándar (barra de vida), 1 = Tiles (infinito, con vidas)
var mod_x2 := false          # modificadores (se guardan)
var mod_nofail := false      # solo Estándar
var mod_perfect := false
var mod_spectator := false   # solo Estándar: juega solo una partida perfecta
var mod_hardcore := false
const MOD_RATE := 2.0        # velocidad del modificador x2
const HARDCORE_WIN := 0.6    # las ventanas de acierto se multiplican por esto en Hardcore
const DIFF_MULT := [0.85, 1.0, 1.1, 1.2, 1.3]   # multiplicador de puntos por dificultad de notas
## Vida que se pierde en modo Estándar (la barra completa vale 1.0; se multiplica por el HP del mapa, ~x1.0 con HP 5).
const DRAIN_EMPTY := 0.12    # tocar donde no hay nota (originalmente 0.05)
const DRAIN_MISS := 0.10     # dejar pasar una nota (como siempre)
var health := 1.0            # barra de vida (modo Estándar)
var health_armed := false    # la barra solo se vacía sola desde que se juega la primera nota
var hp_rate := 5.0           # HPDrainRate del mapa de osu! (0-10)
var base_rate := 1.0         # velocidad base de la canción (2.0 con x2)
var win_mult := 1.0          # multiplicador de ventanas de acierto (Hardcore)
var spectating := false      # esta partida la juega el espectador automático
var mode_menu := false       # menú del botón central de modo
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
var lang := "es"             # idioma de la interfaz: "es" o "en"
var pal: Dictionary = TilesPalette.defaults()   # paleta actual: id de rol -> Color
var perm_asked := false   # ya pedimos el permiso de archivos en esta sesión
var folder_dialog: FileDialog
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
var press_ms := 0
var sel_mode := false            # selección múltiple de canciones (para eliminar)
var sel_ids: Dictionary = {}
var menu_group: Dictionary = {}  # canción del menú de mantener pulsado
var del_ids: Array = []          # canciones pendientes de confirmar eliminación
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

# --- Paleta de colores e idioma ---------------------------------------------

var pal_sel := 0              # rol elegido en la pantalla de paleta
var pal_h := 0.0              # tono, saturación y brillo del rol elegido (se guardan aparte para no perder el tono en grises)
var pal_s := 0.0
var pal_v := 0.0
var pal_drag := -1            # barra que se está arrastrando (0 tono, 1 saturación, 2 brillo)
var pal_drag_id := -999
var pal_reset_armed := false  # "Restablecer todo" espera una segunda pulsación

## Color de un rol de la paleta.
func pcol(id: String) -> Color:
	return pal.get(id, Color.WHITE)

func acol(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Colores derivados de la paleta (así hay menos roles que editar).
func _soft() -> Color:
	return pcol("card").lerp(pcol("accent"), 0.12)

func _ink_soft() -> Color:
	return pcol("ink").lerp(pcol("card"), 0.35)

func _hot() -> Color:
	return pcol("danger").lightened(0.15)

func _ok() -> Color:
	return pcol("good").lerp(Color.WHITE, 0.35)

func _err() -> Color:
	return pcol("danger").lerp(Color.WHITE, 0.4)

func _nav_edge() -> Color:
	return pcol("nav").lerp(pcol("muted"), 0.28)

## Traduce un texto (la clave es el texto en español). Si no hay traducción, lo deja igual.
func T(s: String) -> String:
	if lang == "es":
		return s
	return TilesLang.EN.get(s, s)

func _apply_language() -> void:
	file_dialog.filters = PackedStringArray([T("*.osz ; Beatmaps de osu!")])
	search_edit.placeholder_text = T("Canción, artista o dificultad")
	name_edit.placeholder_text = T("Nombre de la lista")

func _set_lang(code: String) -> void:
	if lang == code:
		return
	lang = code
	_apply_language()
	_apply_filter()
	_save_settings()

## Los cuadros de texto (buscar, nombre de lista) usan nodos, así que se recolorean aparte.
func _apply_edit_theme() -> void:
	for e in [search_edit, name_edit]:
		if e == null:
			continue
		e.add_theme_color_override("font_color", pcol("ink"))
		e.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
		e.add_theme_color_override("caret_color", pcol("accent").darkened(0.08))
		var is_search: bool = e == search_edit
		for style_name in ["normal", "focus", "read_only"]:
			var box := _box(pcol("card") if is_search else _soft(), 24 if is_search else 22)
			box.content_margin_left = 28.0 if is_search else 26.0
			box.content_margin_right = 20.0
			e.add_theme_stylebox_override(style_name, box)
	if search_edit != null:
		search_edit.add_theme_color_override("clear_button_color", Color(0.4, 0.5, 0.6))
		search_edit.add_theme_color_override("clear_button_color_pressed", pcol("accent").darkened(0.08))

func _open_palette() -> void:
	screen = Screen.PALETTE
	_pal_select(pal_sel)

func _pal_id(i: int) -> String:
	return String(TilesPalette.ROLES[i].id)

func _pal_select(i: int) -> void:
	pal_sel = clampi(i, 0, TilesPalette.ROLES.size() - 1)
	var c: Color = pcol(_pal_id(pal_sel))
	pal_h = c.h
	pal_s = c.s
	pal_v = c.v
	pal_reset_armed = false

func _pal_apply_hsv() -> void:
	pal[_pal_id(pal_sel)] = Color.from_hsv(pal_h, pal_s, pal_v)
	_apply_edit_theme()

func _pal_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

func _pal_is_preset(i: int) -> bool:
	var p: Dictionary = TilesPalette.preset(i)
	for k in p:
		if not _pal_close(p[k], pcol(String(k))):
			return false
	return true

func _pal_swatch_rect(i: int) -> Rect2:
	var gap := 14.0
	var cw := (viewport_size.x - 110.0 - 3.0 * gap) / 4.0
	return Rect2(55.0 + (i % 4) * (cw + gap), 300.0 + (i / 4) * 112.0, cw, 100.0)

func _pal_preset_rect(i: int) -> Rect2:
	var gap := 14.0
	var bw := (viewport_size.x - 110.0 - 3.0 * gap) / 4.0
	return Rect2(55.0 + i * (bw + gap), 190.0, bw, 80.0)

func _pal_slider_rect(i: int) -> Rect2:
	return Rect2(95.0, 1110.0 + i * 130.0, viewport_size.x - 190.0, 64.0)

func _pal_btn_rect(i: int) -> Rect2:
	var gap := 20.0
	var bw := (viewport_size.x - 110.0 - gap) / 2.0
	return Rect2(55.0 + i * (bw + gap), 1500.0, bw, 100.0)

func _grad(r: Rect2, c0: Color, c1: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([c0, c1, c1, c0]))

func _draw_palette() -> void:
	_background(); draw_set_transform(Vector2(0, ui_off))
	var w := viewport_size.x
	_button(Rect2(35, 45, 180, 95), "< Volver", pcol("button"))
	_text("PALETA DE COLORES", Vector2(245, 118), 46, Color.WHITE)
	for i in TilesPalette.PRESETS.size():
		_button(_pal_preset_rect(i), String(TilesPalette.PRESETS[i].name), pcol("accent") if _pal_is_preset(i) else pcol("button"))
	for i in TilesPalette.ROLES.size():
		var r := _pal_swatch_rect(i)
		var c: Color = pcol(_pal_id(i))
		_panel(r, c, 20)
		var fg := Color(0.05, 0.08, 0.12) if c.get_luminance() > 0.55 else Color(0.97, 0.98, 1.0)
		_text_fixed(_fit(String(TilesPalette.ROLES[i].name), r.size.x - 20.0, 25), Vector2(r.position.x + 12, r.position.y + 62), 25, fg)
		if i == pal_sel:
			var ring := _box(Color(0, 0, 0, 0), 20)
			ring.border_width_left = 8
			ring.border_width_right = 8
			ring.border_width_top = 8
			ring.border_width_bottom = 8
			ring.border_color = Color.WHITE
			draw_style_box(ring, r)
			var inner := _box(Color(0, 0, 0, 0), 14)
			inner.border_width_left = 3
			inner.border_width_right = 3
			inner.border_width_top = 3
			inner.border_width_bottom = 3
			inner.border_color = Color(0.05, 0.08, 0.12, 0.9)
			draw_style_box(inner, r.grow(-8.0))
	var cur: Color = pcol(_pal_id(pal_sel))
	_text(_fit("%s · #%s" % [T(String(TilesPalette.ROLES[pal_sel].name)), cur.to_html(false).to_upper()], w - 160, 30), Vector2(80, 1050), 30, Color.WHITE)
	var names := ["Tono", "Saturación", "Brillo"]
	var vals := [pal_h, pal_s, pal_v]
	for i in 3:
		var sr := _pal_slider_rect(i)
		_text(names[i], Vector2(sr.position.x, sr.position.y - 16), 26, pcol("muted"))
		if i == 0:
			for k in 6:
				_grad(Rect2(sr.position.x + sr.size.x * k / 6.0, sr.position.y, sr.size.x / 6.0, sr.size.y), Color.from_hsv(k / 6.0, 1.0, 1.0), Color.from_hsv((k + 1) / 6.0, 1.0, 1.0))
		elif i == 1:
			_grad(sr, Color.from_hsv(pal_h, 0.0, pal_v), Color.from_hsv(pal_h, 1.0, pal_v))
		else:
			_grad(sr, Color.from_hsv(pal_h, pal_s, 0.0), Color.from_hsv(pal_h, pal_s, 1.0))
		draw_rect(sr, Color(1, 1, 1, 0.3), false, 3.0)
		var tp := Vector2(sr.position.x + float(vals[i]) * sr.size.x, sr.get_center().y)
		draw_circle(tp, 41.0, Color(0.05, 0.08, 0.12, 0.6))
		draw_circle(tp, 37.0, Color.WHITE)
		draw_circle(tp, 29.0, cur)
	_button(_pal_btn_rect(0), "Restablecer color", pcol("button"))
	_button(_pal_btn_rect(1), "¿Seguro?" if pal_reset_armed else "Restablecer todo", pcol("danger") if pal_reset_armed else pcol("button"))
	_draw_nav()

func _palette_pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if not pressed:
		if input_id == pal_drag_id:
			pal_drag = -1
			pal_drag_id = -999
			_save_settings()
		return
	if _nav_tap(pos):
		return
	pos.y -= ui_off
	if Rect2(35, 45, 180, 95).has_point(pos):
		screen = Screen.SETTINGS
		return
	var was_armed := pal_reset_armed
	pal_reset_armed = false
	for i in 3:
		if _pal_slider_rect(i).grow_individual(40, 45, 40, 45).has_point(pos):
			pal_drag = i
			pal_drag_id = input_id
			_pal_drag_to(pos.x)
			return
	for i in TilesPalette.PRESETS.size():
		if _pal_preset_rect(i).has_point(pos):
			pal = TilesPalette.preset(i)
			_pal_select(pal_sel)
			_apply_edit_theme()
			_save_settings()
			return
	for i in TilesPalette.ROLES.size():
		if _pal_swatch_rect(i).has_point(pos):
			_pal_select(i)
			return
	if _pal_btn_rect(0).has_point(pos):
		pal[_pal_id(pal_sel)] = TilesPalette.ROLES[pal_sel].def
		_pal_select(pal_sel)
		_apply_edit_theme()
		_save_settings()
	elif _pal_btn_rect(1).has_point(pos):
		if was_armed:
			pal = TilesPalette.defaults()
			_pal_select(pal_sel)
			_apply_edit_theme()
			_save_settings()
		else:
			pal_reset_armed = true

func _pal_drag_to(x: float) -> void:
	if pal_drag < 0:
		return
	var r := _pal_slider_rect(pal_drag)
	var t := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	if pal_drag == 0:
		pal_h = minf(t, 0.999)
	elif pal_drag == 1:
		pal_s = t
	else:
		pal_v = t
	_pal_apply_hsv()

func _drag_any(pos: Vector2, relative: Vector2, input_id: int) -> void:
	if screen == Screen.PALETTE:
		if input_id == pal_drag_id:
			_pal_drag_to(pos.x)
		return
	if screen == Screen.SETTINGS:
		if input_id == set_press_id:
			if not set_dragged and pos.distance_to(set_press_pos) > 24.0:
				set_dragged = true
			if set_dragged:
				set_scroll = clampf(set_scroll - relative.y, 0.0, _settings_max_scroll())
		return
	if screen == Screen.GAME and input_id in active_inputs:
		return   # la altura del dedo se fija al tocar: moverlo no cambia dónde se dibuja la larga
	_library_drag(pos, relative, input_id)

# --- Menús de pausa / vida perdida y estrellas de dificultad -----------------

## Botones de los menús de pausa y de vida perdida: 0 arriba (salir/rendirse), 1 reiniciar, 2 continuar (abajo, lo más usado).
func _menu_btn_rect(i: int) -> Rect2:
	return Rect2(170, 830.0 + i * 145.0, viewport_size.x - 340, 120)

## Categorías por estrellas (hasta el máximo indicado, sin incluirlo: 1.99 es Beginner y 2.0 ya es Normal). De fácil (cálido claro) a difícil (fuerte y oscuro).
const STAR_TIERS := [
	{"max": 2.0, "name": "Beginner", "color": Color(1.0, 0.88, 0.45), "dark": true},
	{"max": 4.0, "name": "Normal", "color": Color(1.0, 0.72, 0.30), "dark": true},
	{"max": 5.0, "name": "Medium", "color": Color(0.98, 0.52, 0.25), "dark": false},
	{"max": 6.0, "name": "Hard", "color": Color(0.90, 0.28, 0.26), "dark": false},
	{"max": 8.0, "name": "Very Hard", "color": Color(0.72, 0.13, 0.36), "dark": false},
	{"max": 9.0, "name": "Extreme", "color": Color(0.48, 0.12, 0.50), "dark": false},
	{"max": 999.0, "name": "Master", "color": Color(0.26, 0.10, 0.42), "dark": false},
]
const STAR_CACHE_VERSION := 2   # súbelo si cambias la escala de estimación
var star_cache: Dictionary = {}   # "set_id|versión|tamaño" -> estrellas estimadas (se guarda en settings.cfg)

func _tier_of(st: float) -> int:
	for i in STAR_TIERS.size():
		if st < float(STAR_TIERS[i].max):
			return i
	return STAR_TIERS.size() - 1

func _stars_key(e: Dictionary) -> String:
	return "%s|%s|%d" % [e.get("set_id", ""), e.get("version", ""), int(e.get("size", 0))]

func _cache_stars(e: Dictionary, parsed: Dictionary) -> void:
	star_cache[_stars_key(e)] = OsuImporter.estimate_stars(parsed)

## Estrellas estimadas de una dificultad (-1 si no hay: demo o mapa ilegible). Se calcula una vez y se guarda.
func _stars_of(e: Dictionary) -> float:
	if e.get("demo", false) or not e.has("osu_path"):
		return -1.0
	var k := _stars_key(e)
	if star_cache.has(k):
		return float(star_cache[k])
	var parsed: Dictionary = OsuImporter.parse_osu(FileAccess.get_file_as_string(String(e.osu_path)))
	if not parsed.ok:
		star_cache[k] = -1.0
		return -1.0
	_cache_stars(e, parsed)
	return float(star_cache[k])

## Calcula las estrellas de todas las dificultades de una canción y las ordena de fácil a difícil.
func _ensure_group_stars(g: Dictionary) -> void:
	if g.is_empty() or g.get("stars_sorted", false):
		return
	var before := star_cache.size()
	for e in g.entries:
		_stars_of(e)
	g.entries.sort_custom(func(a, b):
		if a.badge != b.badge:
			return String(a.badge).naturalnocasecmp_to(String(b.badge)) < 0
		return _stars_of(a) < _stars_of(b))
	g["stars_sorted"] = true
	if star_cache.size() != before:
		_save_settings()

func _text_fixed_c(value: String, cx: float, y: float, size: int, color: Color) -> void:
	var w := _font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text_fixed(value, Vector2(cx - w / 2.0, y), size, color)

## Categoría integrada en la fila: píldora translúcida del color de la categoría, con un punto y el nombre
## (sin bloque sólido). dark_bg = true cuando el fondo es oscuro o de color fuerte (preparar, fila actual).
func _draw_star_chip(r: Rect2, st: float, dark_bg := false) -> void:
	var t: Dictionary = STAR_TIERS[_tier_of(st)]
	var c: Color = t.color
	var txt: Color = c.lightened(0.45) if dark_bg else c.darkened(0.42)
	var fill := Color(c.r, c.g, c.b, 0.26 if dark_bg else 0.20)
	var rr := Rect2(r.position.x + 14.0, r.position.y + r.size.y * 0.16, r.size.x - 14.0, r.size.y * 0.68)
	_panel(rr, fill, rr.size.y / 2.0)
	var size := 26 if r.size.y >= 60.0 else 22
	var dot_x := rr.position.x + rr.size.y * 0.5
	draw_circle(Vector2(dot_x, rr.get_center().y), rr.size.y * 0.16, c)
	var tx := (rr.position.x + rr.size.y + rr.end.x) / 2.0 - rr.size.y * 0.25
	_text_fixed_c(String(t.name), tx, rr.get_center().y + size * 0.35, size, txt)

func _diff_pill_rect() -> Rect2:
	return Rect2(80, 602, viewport_size.x - 160, 108)

func _diff_pill_multi() -> bool:
	var g := _group_of(String(current_song.get("set_id", "")))
	return not g.is_empty() and g.entries.size() > 1

## Dificultad de la canción dentro de "preparar": toca para elegir otra de la misma canción.
func _draw_diff_pill() -> void:
	var st := _stars_of(current_song)
	if st < 0.0:
		return
	var r := _diff_pill_rect()
	var multi := _diff_pill_multi()
	_panel(r, Color(0.02, 0.04, 0.09, 0.78), 28)
	_draw_star_chip(Rect2(r.position.x + 10, r.position.y + 10, 200, r.size.y - 20), st, true)
	var tw := r.size.x - 236.0 - (90.0 if multi else 24.0)
	_text(_fit(String(current_song.version), tw, 34), Vector2(r.position.x + 232, r.position.y + (52.0 if multi else 64.0)), 34, Color.WHITE)
	if multi:
		_text(_fit(T("Cambiar dificultad"), tw, 22), Vector2(r.position.x + 232, r.position.y + 88), 22, pcol("muted"))
		var c := Vector2(r.end.x - 48, r.get_center().y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-15, -8), c + Vector2(15, -8), c + Vector2(0, 11)]), pcol("text"))

func _open_diffs() -> void:
	var g := _group_of(String(current_song.get("set_id", "")))
	if g.is_empty() or g.entries.size() < 2:
		return
	_ensure_group_stars(g)
	overlay = "diffs"

func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	_setup_buses()
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	add_child(player)
	sfx_player = AudioStreamPlayer.new()
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	_setup_ambient()
	sfx_fail = _gen_fail()
	sfx_life = _gen_life()
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
	lang = "es" if OS.get_locale_language() == "es" else "en"   # primer arranque: idioma del móvil
	_load_settings()
	_apply_edit_theme()
	_apply_language()
	_migrate_legacy_progress()
	_refresh_library()
	_resize()
	_start_ambient()

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
		Screen.PALETTE:
			screen = Screen.SETTINGS
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
	if amb_on and amb_song and screen != Screen.PREPARE:
		_stop_ambient()
	_ambient_tick(delta)
	if screen == Screen.LIBRARY and press_id != -999 and not dragged and tab == TAB_MUSIC and overlay == "" and open_group.is_empty() and Time.get_ticks_msec() - press_ms > 480:
		_long_press()
	if screen == Screen.GAME and started and not paused and not finished:
		song_time += delta * play_rate
		if game_mode == 0 and not spectating and not _mod_on("nofail") and health_armed and song_time > 0.0 and not life_menu:
			health -= (0.006 + 0.0025 * hp_rate) * delta
			if health <= 0.0:
				health = 0.0
				_game_over("SIN VIDA")
		if spectating and started:
			_auto_play()
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
	for m in marks:
		m.t += delta
	for i in range(marks.size() - 1, -1, -1):
		if marks[i].t >= MARK_TIME:
			marks.remove_at(i)
	for d in dying:
		d.t += delta
	for i in range(dying.size() - 1, -1, -1):
		var dd: Dictionary = dying[i]
		if dd.get("kind", "") == "hold":
			# La larga completada se queda opaca y sigue bajando hasta salir de la pantalla.
			var hbn: float = hit_y - (float(dd.time) - song_time) * speed
			if hbn - float(dd.height) > viewport_size.y:
				dying.remove_at(i)
		elif dd.t >= DIE_TIME:
			dying.remove_at(i)
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

## Espectador: toca cada nota justo a su hora (partida perfecta).
func _auto_play() -> void:
	for i in range(first_idx, notes.size()):
		var n: Dictionary = notes[i]
		if n.type != "start" and n.time - song_time > 0.05:
			break
		if n.done or n.holding or n.type == "start":
			continue
		if song_time >= n.time:
			var aid := -300 - int(n.lane)
			active_inputs[aid] = n.lane
			input_x[aid] = (float(n.lane) + 0.5) * viewport_size.x / LANES
			input_y[aid] = hit_y
			_try_hit(int(n.lane), aid)

## Altura del dedo que sostiene una larga (con teclado: la línea de golpeo).
func _hold_y(note: Dictionary) -> float:
	var iid = note.get("input_id", null)
	if iid != null and input_y.has(iid):
		return clampf(float(input_y[iid]), 0.0, hit_y)
	return hit_y

func _update_notes() -> void:
	for i in range(first_idx, notes.size()):
		var note: Dictionary = notes[i]
		if note.type != "start" and note.time - song_time > ahead:
			break
		if note.done:
			continue
		if note.type == "hold" and note.holding:
			var held: bool = note.input_id in active_inputs and active_inputs[note.input_id] == note.lane
			var end_time: float = note.time + note.duration - clampf((hit_y - _hold_y(note)) / speed, 0.0, 0.35)
			if not held and song_time < end_time - 0.12:
				_release_hold(note)
			elif song_time >= end_time:
				note.done = true
				note.holding = false
				dying.append({"lane": note.lane, "time": float(note.time), "height": maxf(viewport_size.x / LANES * 0.83 + 90.0, float(note.duration) * speed), "t": 0.0, "kind": "hold"})
				_hit(note.lane, "PERFECT", 180, hit_y)
		elif note.type != "start" and song_time > note.time + HIT_LATE * win_mult * play_rate:
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
		_fade_out(1.2)
		await get_tree().create_timer(1.2).timeout
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
		banner_text = T("ESTRELLA %d/3") % stars
	else:
		crowns += 1
		banner_text = T("CORONA %d/3") % crowns
	banner_kind = kind
	banner_time = 1.8
	_store_infinite_best()

func _next_lap() -> void:
	_check_awards(true)
	lap += 1
	lap_factor = 1.0 + 0.5 * float(lap - 1)
	lap_banner_text = T("VUELTA %d · x%.1f") % [lap, lap_factor]
	lap_banner_time = 2.4
	play_rate = base_rate * (1.0 + LAP_SONG_STEP * float(lap - 1))   # la canción suena un poco más rápido
	player.pitch_scale = play_rate
	# Velocidad real de caída = BASE * mult * lap_factor (como antes); aquí va por segundo de canción.
	speed = BASE_SPEED * _effective_mult() * lap_factor * base_rate / play_rate
	_store_infinite_best()
	ahead = hit_y / speed + 0.15
	lead_in = maxf(0.0, hit_y / speed + 0.05 - first_note_time) if use_lead_in else 0.0
	for n in notes:
		if n.type == "start":
			continue
		n.done = false; n.holding = false; n.released = false; n.input_id = -999
	_assign_tap_heights()
	first_idx = 0
	dying.clear()
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
	var pen := roundi(score * run_mult)
	var nb := {
		"stars": maxi(stars, int(old.get("stars", 0))),
		"crowns": maxi(crowns, int(old.get("crowns", 0))),
		"laps": maxi(lap, int(old.get("laps", 0))),
		"score": maxi(pen, int(old.get("score", 0))),
		"mods": _mods_text() if pen > int(old.get("score", 0)) else String(old.get("mods", "")),
	}
	if nb.stars > int(old.get("stars", 0)) or nb.crowns > int(old.get("crowns", 0)) or nb.laps > int(old.get("laps", 0)) or nb.score > int(old.get("score", 0)):
		run_record = true
	bests[key] = nb
	_save_settings()

func _finish_infinite() -> void:
	_store_infinite_best()
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
	var fill := pcol("gold") if earned else Color(0.45, 0.5, 0.6, 0.5)
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
		_drag_any(event.position, event.relative, event.index)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_any(event.position, event.relative, -1)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if screen == Screen.LIBRARY:
			scroll_y += -120.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0
			_clamp_scroll()
		elif screen == Screen.SETTINGS:
			set_scroll = clampf(set_scroll + (-120.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 120.0), 0.0, _settings_max_scroll())
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

func _settings_max_scroll() -> float:
	return maxf(0.0, SETTINGS_END - (viewport_size.y - NAV_H - ui_off))

func _settings_pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if pressed:
		if _nav_tap(pos):
			return
		set_press_id = input_id
		set_press_pos = pos
		set_dragged = false
	elif input_id == set_press_id:
		set_press_id = -999
		if not set_dragged:
			pos.y += set_scroll - ui_off
			_settings_tap(pos)

func _settings_tap(pos: Vector2) -> void:
	var w := viewport_size.x
	if Rect2(80, 330, w - 160, 180).has_point(pos):
		show_bg = not show_bg; _reload_bg(); _save_settings()
	elif Rect2(80, 870, w - 160, 180).has_point(pos):
		show_thumbs = not show_thumbs; _save_settings()
	elif show_bg and Rect2(130, 690, 170, 110).has_point(pos): _adjust_bg(-0.05)
	elif show_bg and Rect2(w - 300, 690, 170, 110).has_point(pos): _adjust_bg(0.05)
	elif _lang_rect(0).has_point(pos): _set_lang("es")
	elif _lang_rect(1).has_point(pos): _set_lang("en")
	elif Rect2(80, 1290, w - 160, 180).has_point(pos): _open_palette()
	elif Rect2(80, 1500, w - 160, 180).has_point(pos):
		sfx_on = not sfx_on; _save_settings()
	elif Rect2(80, 1710, w - 160, 180).has_point(pos):
		amb_enabled = not amb_enabled
		_save_settings()
		if amb_enabled:
			amb_retry = 0.0
		else:
			_stop_ambient()
	elif Rect2(130, 2040, 170, 110).has_point(pos): _adjust_music_vol(-0.1)
	elif Rect2(w - 300, 2040, 170, 110).has_point(pos): _adjust_music_vol(0.1)
	elif Rect2(130, 2620, 170, 110).has_point(pos): _adjust_note_len(-0.1)
	elif Rect2(w - 300, 2620, 170, 110).has_point(pos): _adjust_note_len(0.1)
	elif Rect2(130, 2330, 170, 110).has_point(pos): _adjust_sfx_vol(-0.1)
	elif Rect2(w - 300, 2330, 170, 110).has_point(pos): _adjust_sfx_vol(0.1)

func _key_lane(event: InputEventKey) -> int:
	var key: Key = event.physical_keycode
	if key == KEY_D: return 0
	if key == KEY_F: return 1
	if key == KEY_J: return 2
	if key == KEY_K: return 3
	return -1

func _pointer(pos: Vector2, pressed: bool, input_id: int) -> void:
	if screen == Screen.SETTINGS:
		_settings_pointer(pos, pressed, input_id)
		return
	if screen == Screen.PALETTE:
		_palette_pointer(pos, pressed, input_id)
		return
	if screen == Screen.LIBRARY:
		_library_pointer(pos, pressed, input_id)
		return
	if not pressed:
		active_inputs.erase(input_id)
		return
	if screen == Screen.PREPARE and overlay != "":
		_overlay_tap(pos)
		return
	if screen == Screen.PREPARE or screen == Screen.RESULTS:
		pos.y -= ui_off
	if screen == Screen.PREPARE:
		var pw := viewport_size.x
		if Rect2(100, 1060, pw - 200, 130).has_point(pos): _start_game()
		elif Rect2(35, 45, 180, 95).has_point(pos): _stop_audio(); screen = Screen.LIBRARY
		elif Rect2(235, 45, pw - 270, 95).has_point(pos): overlay = "addto"
		elif Rect2(60, 175, 110, 110).has_point(pos): _toggle_preview()
		elif _diff_pill_rect().has_point(pos) and _diff_pill_multi(): _open_diffs()
		elif Rect2(110, 1295, 150, 90).has_point(pos): _adjust_diff(-1)
		elif Rect2(pw - 260, 1295, 150, 90).has_point(pos): _adjust_diff(1)
		elif Rect2(110, 1400, 150, 90).has_point(pos): _adjust_speed(-SPEED_STEP)
		elif Rect2(pw - 260, 1400, 150, 90).has_point(pos): _adjust_speed(SPEED_STEP)
		elif Rect2(280, 1400, pw - 560, 90).has_point(pos): speed_auto = not speed_auto; _save_settings()
		elif _prepare_mod_tap(pos): pass
	elif screen == Screen.GAME:
		if finished:
			return
		if life_menu:
			pos.y -= ui_off
			if life_menu_lock <= 0.0:
				if _menu_btn_rect(0).has_point(pos): _give_up()
				elif _menu_btn_rect(1).has_point(pos): _restart_run()
				elif _menu_btn_rect(2).has_point(pos): _continue_after_life()
			return
		if resume_pending:
			var rl: int = clampi(int(pos.x / (viewport_size.x / LANES)), 0, LANES - 1)
			active_inputs[input_id] = rl
			input_y[input_id] = pos.y
			input_x[input_id] = pos.x
			_try_hit(rl, input_id)
			return
		if Rect2(viewport_size.x - 145, 35 + top_inset, 110, 100).has_point(pos):
			_set_paused(not paused)
			return
		if paused:
			pos.y -= ui_off
			if _menu_btn_rect(0).has_point(pos): _go_prepare()
			elif _menu_btn_rect(1).has_point(pos): _restart_run()
			elif _menu_btn_rect(2).has_point(pos): _set_paused(false)
			return
		var lane: int = clampi(int(pos.x / (viewport_size.x / LANES)), 0, LANES - 1)
		active_inputs[input_id] = lane
		input_y[input_id] = pos.y
		input_x[input_id] = pos.x
		_try_hit(lane, input_id)
	elif screen == Screen.RESULTS:
		if _results_retry_rect().has_point(pos): _start_game()
		elif _results_songs_rect().grow(20).has_point(pos): open_group = {}; screen = Screen.LIBRARY

## Un tap no debe solaparse con la siguiente nota de su carril.
func _assign_tap_heights() -> void:
	var next_time := {}
	for i in range(notes.size() - 1, -1, -1):
		var n: Dictionary = notes[i]
		if n.type == "start":
			continue
		n.height = NORMAL_HEIGHT * note_len
		if n.type == "tap" and next_time.has(n.lane):
			n.height = clampf((next_time[n.lane] - n.time) * speed - 6.0, 50.0, NORMAL_HEIGHT * note_len)
		next_time[n.lane] = n.time

func _start_game() -> void:
	_stop_ambient()
	_stop_audio()
	screen = Screen.GAME
	if not current_song.is_empty():
		var sfx_k := "_inf" if game_mode == 1 else ""
		last_played["id" + sfx_k] = String(current_song.get("set_id", "demo"))
		last_played["version" + sfx_k] = String(current_song.get("version", ""))
		_save_settings()
	infinite_run = game_mode == 1
	spectating = _mod_on("spectator")
	base_rate = MOD_RATE if _mod_on("x2") else 1.0
	win_mult = HARDCORE_WIN if _mod_on("hardcore") else 1.0
	hp_rate = clampf(float(current_parsed.get("hp", 5.0)), 0.0, 10.0)
	health = 1.0
	health_armed = false
	lap = 1; lap_factor = 1.0; award_idx = 0; stars = 0; crowns = 0
	banner_time = 0.0; lap_banner_time = 0.0; bg_blend = 0.0
	play_rate = base_rate; player.pitch_scale = base_rate; run_record = false
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
		note.height = NORMAL_HEIGHT * note_len
		notes.append(note)
	_assign_tap_heights()
	first_idx = 0
	player.stream = audio_stream
	active_inputs.clear(); effects.clear(); dying.clear(); marks.clear()
	song_time = -lead_in; started = false; paused = false; finished = false
	score = 0; combo = 0; max_combo = 0; hits = 0; misses = 0
	perfects = 0; greats = 0; goods = 0; empties = 0
	run_lives = lives_setting if game_mode == 1 else 0
	lives_left = run_lives
	life_menu = false; life_menu_lock = 0.0; resume_pending = false; resume_idxs = []; grace_time = 0.0
	failed = false; fail_text = ""; run_mult = _mods_mult()

func _try_hit(lane: int, input_id: int) -> void:
	if resume_pending:
		_resume_with(lane, input_id)
		return
	if paused or finished:
		return
	if spectating and started and input_id > -300:
		return
	if not started:
		for note in notes:
			if note.type == "start" and note.lane == lane and not note.done:
				note.done = true; started = true; song_time = -lead_in; audio_started = false
				_hit(lane, "COMENZAR", 0, hit_y)
				return
		_mark(lane, input_id)
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
		var early: float = clampf(float(note.height) / speed, 0.2, 0.6) * win_mult
		var signed_diff: float = song_time - note.time
		if signed_diff < -early * play_rate or signed_diff > HIT_LATE * win_mult * play_rate: continue
		best_diff = abs(signed_diff); best = note
		break  # la más antigua pendiente del carril
	if best.is_empty():
		combo = 0; empties += 1; _set_judgement("VACÍO", 0.4)
		_mark(lane, input_id)
		_lose_life(DRAIN_EMPTY)
		return
	if best.type == "hold":
		best.holding = true; best.input_id = input_id
	else:
		best.done = true
		dying.append({"lane": lane, "time": float(best.time), "height": float(best.height), "t": 0.0})
		var judgement := "PERFECT" if best_diff <= PERFECT_WINDOW * win_mult * play_rate else ("GREAT" if best_diff <= GREAT_WINDOW * win_mult * play_rate else "GOOD")
		var points := 100 if judgement == "PERFECT" else (75 if judgement == "GREAT" else 50)
		_hit(lane, judgement, points, hit_y)

func _hit(lane: int, text: String, points: int, effect_y: float) -> void:
	_health_gain(text)
	hits += 1; combo += 1; max_combo = max(max_combo, combo); score += points + min(combo, 50)
	_set_judgement(text, 0.55); combo_pop = 0.18
	match text:
		"PERFECT": perfects += 1
		"GREAT": greats += 1
		"GOOD": goods += 1

func _set_judgement(text: String, duration: float) -> void:
	last_judgement = text; judgement_time = duration; judgement_total = duration

func _judgement_color(text: String) -> Color:
	match text:
		"PERFECT": return pcol("perfect")
		"GREAT": return pcol("great")
		"GOOD": return pcol("good")
		"MISS", "VACÍO": return pcol("miss")
	return Color.WHITE

func _miss(lane: int, effect_y: float) -> void:
	health_armed = true
	misses += 1; combo = 0; _set_judgement("MISS", 0.6)
	_lose_life(DRAIN_MISS)

# --- Modo Vidas ----------------------------------------------------------

## Cada fallo (nota que se va, hold soltado, toque en vacío) cuesta una vida.
## Con vidas restantes: pausa y menú (rendirse / continuar). Sin vidas: fin de la partida.
func _lose_life(amount := 0.08) -> void:
	if finished or life_menu or grace_time > 0.0 or spectating:
		return
	if _mod_on("perfect"):
		_game_over("FALLASTE")
		return
	if game_mode == 0:
		# Estándar: cada fallo resta vida (más con un HP alto); a 0 se pierde, salvo Sin fallo.
		health -= amount * (0.7 + 0.06 * hp_rate)
		if health <= 0.0:
			health = 0.0
			if not _mod_on("nofail"):
				_game_over("SIN VIDA")
		return
	if run_lives <= 0:
		return
	# Con N vidas se pueden fallar N veces y seguir; el fallo N+1 (con 0 vidas) termina.
	if lives_left <= 0:
		_game_over("SIN VIDAS")
	else:
		lives_left -= 1
		life_menu = true
		life_menu_lock = 0.7
		_play_sfx(sfx_life)
		_pause_with_fade()

func _game_over(text: String) -> void:
	failed = true; fail_text = text; finished = true
	_play_sfx(sfx_fail)
	_fade_slow(0.85)
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

func _mod_on(id: String) -> bool:
	match id:
		"x2": return mod_x2
		"nofail": return game_mode == 0 and mod_nofail
		"perfect": return mod_perfect
		"spectator": return game_mode == 0 and mod_spectator
		"hardcore": return mod_hardcore
	return false

## Multiplicador de puntos de todos los modificadores activos.
func _mods_mult() -> float:
	var m := 1.0
	if _mod_on("x2"): m *= 1.3
	if _mod_on("hardcore"): m *= 1.15
	if _mod_on("nofail"): m *= 0.5
	if _mod_on("perfect"): m *= 1.1
	m *= float(DIFF_MULT[diff_level])
	if game_mode == 1:
		m *= _lives_mult(lives_setting)
	return m

func _mods_text() -> String:
	var parts: Array = []
	if _mod_on("x2"): parts.append("x2")
	if _mod_on("nofail"): parts.append(T("Sin fallo"))
	if _mod_on("perfect"): parts.append("Perfect")
	if _mod_on("spectator"): parts.append(T("Espectador"))
	if _mod_on("hardcore"): parts.append("Hardcore")
	if diff_level != 1: parts.append(T(String(DIFFICULTY_LEVELS[diff_level].name)))
	if game_mode == 1: parts.append(T("%d vidas") % lives_setting)
	return " · ".join(parts)

func _health_gain(text: String) -> void:
	health_armed = true
	if game_mode != 0:
		return
	match text:
		"PERFECT": health += 0.030
		"GREAT": health += 0.022
		"GOOD": health += 0.012
	health = minf(1.0, health)

## Puntos x1.00 con 3 vidas; cada vida extra resta ~7,1 % hasta x0.50 con 10.
func _lives_mult(n: int) -> float:
	return 1.0 - float(n - LIVES_MIN) * 0.5 / float(LIVES_MAX - LIVES_MIN)

func _adjust_lives(delta: int) -> void:
	lives_setting = clampi(lives_setting + delta, LIVES_MIN, LIVES_MAX)
	_save_settings()

func _mod_ids() -> Array:
	if game_mode == 0:
		return ["x2", "nofail", "perfect", "spectator", "hardcore"]
	return ["x2", "perfect", "hardcore"]

func _mod_label(id: String) -> String:
	match id:
		"x2": return "Velocidad x2"
		"nofail": return "Sin fallo"
		"perfect": return "Perfect"
		"spectator": return "Espectador"
		"hardcore": return "Hardcore"
	return id

func _mod_rect(i: int) -> Rect2:
	var cw2 := (viewport_size.x - 240.0 - 16.0) / 2.0
	return Rect2(110.0 + (i % 2) * (cw2 + 16.0), 1520.0 + floorf(i / 2.0) * 100.0, cw2, 90.0)

func _toggle_mod(id: String) -> void:
	match id:
		"x2": mod_x2 = not mod_x2
		"nofail":
			mod_nofail = not mod_nofail
			if mod_nofail: mod_perfect = false
		"perfect":
			mod_perfect = not mod_perfect
			if mod_perfect: mod_nofail = false
		"spectator": mod_spectator = not mod_spectator
		"hardcore": mod_hardcore = not mod_hardcore
	_save_settings()

func _prepare_mod_tap(pos: Vector2) -> bool:
	var ids := _mod_ids()
	for i in ids.size():
		if _mod_rect(i).has_point(pos):
			_toggle_mod(String(ids[i]))
			return true
	if game_mode == 1:
		if Rect2(130, 1720, 170, 90).has_point(pos):
			_adjust_lives(-1)
			return true
		if Rect2(viewport_size.x - 300, 1720, 170, 90).has_point(pos):
			_adjust_lives(1)
			return true
	return false

## Vidas como barras horizontales gruesas (las restantes encendidas, de izquierda a derecha).
func _draw_lives_bars(x: float, y: float, bar_w: float, bar_h: float, gap: float) -> void:
	for i in run_lives:
		var r := Rect2(x + i * (bar_w + gap), y, bar_w, bar_h)
		draw_rect(r.grow(3.0), Color(0.04, 0.16, 0.32, 0.9))
		draw_rect(r, _hot() if i < lives_left else Color(0.4, 0.46, 0.56, 0.6))

## Toque en vacío: círculo rojo suave justo donde pusiste el dedo (0.06 s).
func _mark(lane: int, input_id: int) -> void:
	var lane_w := viewport_size.x / LANES
	var p := Vector2((lane + 0.5) * lane_w, hit_y)
	if input_id >= 0 and input_x.has(input_id) and input_y.has(input_id):
		p = Vector2(float(input_x[input_id]), float(input_y[input_id]))
	elif input_id == -1 and input_x.has(-1) and input_y.has(-1):
		p = Vector2(float(input_x[-1]), float(input_y[-1]))
	marks.append({"pos": p, "t": 0.0})

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
	search_edit.add_theme_color_override("font_color", pcol("ink"))
	search_edit.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
	search_edit.add_theme_color_override("caret_color", pcol("accent").darkened(0.08))
	search_edit.add_theme_color_override("clear_button_color", Color(0.4, 0.5, 0.6))
	search_edit.add_theme_color_override("clear_button_color_pressed", pcol("accent").darkened(0.08))
	for style_name in ["normal", "focus", "read_only"]:
		var box := _box(pcol("card"), 24)
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
		_show_status(T("Importado: %s (%d dificultades)") % [result.title, result.count], false)
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
		_show_status(T("Android no deja usar esa carpeta. Se usa la de por defecto: %s") % library_dir, true, 8.0)
		return
	library_dir = path
	_migrate_legacy_progress()
	_save_settings()
	_apply_filter()
	_show_status(T("Carpeta de canciones: %s") % path, false)

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

## Los récords, listas y favoritas ya solo se guardan dentro de la app (settings.cfg).
## Si queda un progreso.cfg de versiones anteriores, se importa UNA vez y se renombra.
func _migrate_legacy_progress() -> void:
	var path := _progress_path()
	if path == "" or not FileAccess.file_exists(path):
		return
	if _merge_progress_file():
		_save_settings()
	DirAccess.rename_absolute(path, path.get_base_dir().path_join("progreso_antiguo.cfg"))

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
		last_played["id"] = String(cfg.get_value("library", "last_id", ""))
		last_played["version"] = String(cfg.get_value("library", "last_version", ""))
		changed = true
	if String(last_played.get("id_inf", "")) == "" and String(cfg.get_value("library", "last_id_inf", "")) != "":
		last_played["id_inf"] = String(cfg.get_value("library", "last_id_inf", ""))
		last_played["version_inf"] = String(cfg.get_value("library", "last_version_inf", ""))
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
		_show_status(T("Exportando %d/%d...") % [done + 1, todo.size()], false, 60.0)
		await get_tree().process_frame
		var osz_name := "%s [%s].osz" % [OsuImporter.safe_name(String(g.title)), g.id]
		if _zip_dir(OsuImporter.SONGS_DIR.path_join(String(g.id)), backup.path_join(osz_name)):
			done += 1
		else:
			failed += 1
	var msg := T("Exportadas %d canciones nuevas (%d ya tenían copia)") % [done, total - todo.size()]
	if failed > 0:
		msg += T(", %d con error") % failed
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
	_migrate_legacy_progress()
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
			_show_status(T("Restaurando %d/%d...") % [done, total], false, 60.0)
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
			_show_status(T("Importando %d/%d...") % [done, total], false, 60.0)
			await get_tree().process_frame
			good = OsuImporter.import_osz(ipath).ok
		if good:
			if _backup_copy(ipath, backup, id, f):
				DirAccess.remove_absolute(ipath)
			imported += 1
		else:
			failed += 1
	_refresh_library()
	var msg := T("Listo: %d importadas, %d restauradas (vi %d en Por importar y %d en Importadas)") % [imported, restored, inbox_files.size(), backup_files.size()]
	if failed > 0:
		msg += T(", %d con error") % failed
	if total == 0:
		msg = T("No veo ningún .osz en \"%s\" ni en \"%s\" (%s). Deja ahí tus .osz y pulsa Recargar. Si ya están, falta el permiso: Ajustes de Android, Apps, Tiles FOSS, Permisos, Archivos, permitir administrar todos los archivos.") % [INBOX_NAME, BACKUP_NAME, library_dir]
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
	status_text = T(text); status_error = is_error; status_time = seconds

# --- Barra inferior (Inicio / Música / Archivos / Ajustes) ----------------

func _nav_rect(i: int) -> Rect2:
	var cw := viewport_size.x / 4.0
	return Rect2(i * cw, viewport_size.y - NAV_H, cw, NAV_H)

func _nav_active() -> int:
	return 3 if screen == Screen.SETTINGS or screen == Screen.PALETTE else tab

func _mode_btn_center() -> Vector2:
	return Vector2(viewport_size.x / 2.0, _nav_curve_y(viewport_size.x / 2.0) + 58.0)

func _mode_btn_rect() -> Rect2:
	var c := _mode_btn_center()
	return Rect2(c.x - 62, c.y - 62, 124, 124)

func _mode_opt_rect(i: int) -> Rect2:
	var c := _mode_btn_center()
	return Rect2(viewport_size.x / 2.0 - 230.0, c.y - 200.0 - i * 135.0, 460, 112)

func _set_game_mode(i: int) -> void:
	if game_mode == i:
		return
	game_mode = i
	home_dirty = true
	_save_settings()
	# La música de inicio cambia a la última canción del modo nuevo.
	if amb_on and not amb_song:
		_start_ambient()

func _draw_mode_icon(m: int, c: Vector2, s: float, col: Color) -> void:
	if m == 0:
		draw_rect(Rect2(c.x - s, c.y - s * 0.25, s * 0.55, s * 1.15), col)
		draw_rect(Rect2(c.x - s * 0.275, c.y - s * 0.95, s * 0.55, s * 1.85), col)
		draw_rect(Rect2(c.x + s * 0.45, c.y - s * 0.55, s * 0.55, s * 1.45), col)
	else:
		var pts := PackedVector2Array()
		for k in 41:
			var t := TAU * k / 40.0
			var d := 1.0 + sin(t) * sin(t)
			pts.append(c + Vector2(s * 1.35 * cos(t) / d, s * 1.35 * sin(t) * cos(t) / d))
		draw_polyline(pts, col, s * 0.34, true)

func _draw_mode_button() -> void:
	var c := _mode_btn_center()
	var col := pcol("accent") if game_mode == 0 else pcol("violet")
	draw_circle(c + Vector2(0, 5), 52.0, Color(0, 0, 0, 0.25))
	draw_circle(c, 52.0, col)
	draw_arc(c, 47.0, PI * 1.12, PI * 1.88, 16, Color(1, 1, 1, 0.35), 5.0)
	draw_arc(c, 55.0, 0.0, TAU, 40, Color.WHITE, 5.0)
	_draw_mode_icon(game_mode, c, 20.0, Color.WHITE)
	_text_centered("Estándar" if game_mode == 0 else "Tiles", c.x, c.y + 38.0 + 30.0 + 22.0, 28, Color.WHITE)

func _draw_mode_menu() -> void:
	draw_rect(Rect2(0, 0, viewport_size.x, _nav_curve_y(viewport_size.x / 2.0)), Color(0, 0, 0, 0.55))
	for i in 2:
		var r := _mode_opt_rect(i)
		var col := pcol("accent") if i == 0 else pcol("violet")
		if i != game_mode:
			col = col.darkened(0.35)
		_panel(r, col, 56)
		if i == game_mode:
			draw_style_box(_outline_box(56), r)
		_draw_mode_icon(i, Vector2(r.position.x + 70, r.get_center().y), 22.0, Color.WHITE)
		_text("Estándar" if i == 0 else "Tiles", Vector2(r.position.x + 130, r.get_center().y + 13), 40, Color.WHITE)

func _outline_box(radius: float) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.draw_center = false
	b.border_width_left = 5
	b.border_width_right = 5
	b.border_width_top = 5
	b.border_width_bottom = 5
	b.border_color = Color.WHITE
	b.corner_radius_top_left = int(radius)
	b.corner_radius_top_right = int(radius)
	b.corner_radius_bottom_left = int(radius)
	b.corner_radius_bottom_right = int(radius)
	return b

func _nav_tap(pos: Vector2) -> bool:
	if mode_menu:
		mode_menu = false
		for i in 2:
			if _mode_opt_rect(i).has_point(pos):
				_set_game_mode(i)
				return true
		return true
	if _mode_btn_rect().has_point(pos):
		mode_menu = true
		return true
	for i in 4:
		if _nav_rect(i).has_point(pos):
			_go_tab(i)
			return true
	return false

func _go_tab(i: int) -> void:
	mode_menu = false
	open_group = {}
	sel_mode = false
	sel_ids = {}
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
	draw_colored_polygon(body, pcol("nav"))
	draw_polyline(top, _nav_edge(), 4.0)
	var labels := ["Inicio", "Música", "Archivos", "Ajustes"]
	var colors := [pcol("nav_home"), pcol("nav_music"), pcol("nav_files"), pcol("nav_settings")]
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
		_text_centered(labels[i], cx, ytop + 58.0 + 38.0 + 30.0, 28, Color.WHITE if on else pcol("muted").lerp(Color.WHITE, 0.25))
	_draw_mode_button()
	if mode_menu:
		_draw_mode_menu()

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

func _card_at(pos: Vector2) -> Dictionary:
	var w := viewport_size.x
	if pos.y < LIST_TOP - 22.0 or pos.y > _list_bottom() or pos.x < 55.0 or pos.x > w - 55.0:
		return {}
	var offset := pos.y - LIST_TOP + scroll_y
	var idx := int(offset / (CARD_H + CARD_GAP))
	if offset >= 0.0 and fmod(offset, CARD_H + CARD_GAP) <= CARD_H and idx < view_groups.size():
		return view_groups[idx]
	return {}

func _deletable(g: Dictionary) -> bool:
	return not g.is_empty() and not g.has("playlist_idx") and not g.get("in_playlist", false) and String(g.get("id", "")) != "demo"

## Mantener pulsada una canción: abre el menú de opciones (Seleccionar / Eliminar).
func _long_press() -> void:
	var pos := press_pos
	press_id = -999
	if sel_mode:
		return
	var g := _card_at(pos)
	if not _deletable(g):
		return
	Input.vibrate_handheld(40)
	menu_group = g
	overlay = "songmenu"

func _exit_select() -> void:
	sel_mode = false
	sel_ids = {}

func _ask_delete(ids: Array) -> void:
	if ids.is_empty():
		return
	del_ids = ids.duplicate()
	overlay = "delconfirm"

func _sel_cancel_rect() -> Rect2:
	return Rect2(viewport_size.x - 300, 150.0 + top_inset, 245, 95)

func _sel_delete_rect() -> Rect2:
	return Rect2(viewport_size.x - 590, 150.0 + top_inset, 270, 95)

func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove_dir_recursive(path.path_join(d))
	DirAccess.remove_absolute(path)

## Borra canciones con todas sus dificultades: la carpeta extraída, su copia en Importadas
## (si no, "Recargar" la restauraría), sus récords, favoritas y apariciones en listas.
func _delete_songs(ids: Array) -> void:
	var count := 0
	for raw in ids:
		var sid := String(raw)
		if sid == "" or sid == "demo":
			continue
		count += 1
		_remove_dir_recursive(OsuImporter.SONGS_DIR.path_join(sid))
		if library_dir != "":
			for folder in [library_dir.path_join(BACKUP_NAME), library_dir.path_join(INBOX_NAME)]:
				if not DirAccess.dir_exists_absolute(folder):
					continue
				for f in _osz_files(folder):
					var fpath: String = folder.path_join(f)
					var fid := _id_from_name(f)
					if fid == "":
						fid = FileAccess.get_md5(fpath).substr(0, 10)
					if fid == sid:
						DirAccess.remove_absolute(fpath)
		for key in bests.keys():
			if String(key).begins_with(sid + "|"):
				bests.erase(key)
		favorites.erase(sid)
		for pl in playlists:
			var kept: Array = []
			for r in pl.refs:
				if not String(r).begins_with(sid + "|"):
					kept.append(r)
			pl.refs = kept
		if String(last_played.get("id", "")) == sid:
			last_played["id"] = ""
			last_played["version"] = ""
		if String(last_played.get("id_inf", "")) == sid:
			last_played["id_inf"] = ""
			last_played["version_inf"] = ""
	_exit_select()
	overlay = ""
	_refresh_library()
	_save_settings()
	_show_status(T("Eliminadas: %d") % count, false)

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
				out.append({"playlist_idx": i, "id": "pl%d" % i, "title": pname, "artist": T("1 canción") if n == 1 else T("%d canciones") % n, "creator": "", "entries": []})
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
	name_edit.add_theme_color_override("font_color", pcol("ink"))
	name_edit.add_theme_color_override("font_placeholder_color", Color(0.5, 0.6, 0.7))
	name_edit.add_theme_color_override("caret_color", pcol("accent").darkened(0.08))
	for style_name in ["normal", "focus", "read_only"]:
		var box := _box(_soft(), 22)
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
	elif overlay == "diffs":
		var gd := _group_of(String(current_song.get("set_id", "")))
		var nd: int = gd.entries.size() if not gd.is_empty() else 0
		var rh := clampf((viewport_size.y - 200.0 - 160.0 - 90.0) / maxf(nd, 1.0) - 14.0, 64.0, 100.0)
		h = 160.0 + nd * (rh + 14.0) + 90.0
		py = (viewport_size.y - h) / 2.0
		for i in nd:
			rows.append(Rect2(px + 30, py + 140 + i * (rh + 14.0), pw - 60, rh))
	elif overlay == "songmenu":
		h = 160.0 + 2 * 114.0 + 10.0
		py = (viewport_size.y - h) / 2.0
		for i in 2:
			rows.append(Rect2(px + 30, py + 140 + i * 114.0, pw - 60, 100))
	elif overlay == "delconfirm":
		h = 560.0
		py = (viewport_size.y - h) / 2.0
		var bw2 := (pw - 90.0) / 2.0
		extra["cancel"] = Rect2(px + 30, py + h - 140, bw2, 100)
		extra["ok"] = Rect2(px + 60 + bw2, py + h - 140, bw2, 100)
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
	var ink := pcol("ink")
	var soft := _soft()
	var accent := pcol("accent")
	_panel(panel, pcol("card"), 34)
	var title := "Ordenar por"
	if overlay == "addto":
		title = "Añadir a lista"
	elif overlay == "newlist":
		title = "Nueva lista"
	elif overlay == "songmenu":
		title = _fit(String(menu_group.get("title", "")), panel.size.x - 80, 44)
	elif overlay == "delconfirm":
		title = "Eliminar canciones"
	elif overlay == "diffs":
		title = "Elegir dificultad"
	_text(title, Vector2(panel.position.x + 40, panel.position.y + 86), 44, ink)
	if overlay == "sort":
		for i in lay.rows.size():
			var r: Rect2 = lay.rows[i]
			_panel(r, accent if i == sort_mode else soft, 22)
			_text(SORT_MODES[i], Vector2(r.position.x + 36, r.get_center().y + 13), 36, Color.WHITE if i == sort_mode else ink)
	elif overlay == "diffs":
		var gd2 := _group_of(String(current_song.get("set_id", "")))
		for i in lay.rows.size():
			var rr: Rect2 = lay.rows[i]
			var ee: Dictionary = gd2.entries[i]
			var cur: bool = _ref(ee) == _ref(current_song)
			_panel(rr, accent if cur else soft, 22)
			var stv := _stars_of(ee)
			var vw2 := rr.size.x - 60.0
			if stv >= 0.0:
				_draw_star_chip(Rect2(rr.end.x - 214.0, rr.position.y + 8.0, 204.0, rr.size.y - 16.0), stv, cur)
				vw2 -= 214.0
			_text(_fit(String(ee.version), vw2, 34), Vector2(rr.position.x + 30, rr.get_center().y + 12), 34, Color.WHITE if cur else ink)
		_text("Categoría estimada por el juego", Vector2(panel.position.x + 40, panel.end.y - 36), 22, _ink_soft())
	elif overlay == "songmenu":
		var r0: Rect2 = lay.rows[0]
		_panel(r0, soft, 22)
		_text("Seleccionar", Vector2(r0.position.x + 36, r0.get_center().y + 13), 36, ink)
		var r1: Rect2 = lay.rows[1]
		_panel(r1, pcol("danger"), 22)
		_text("Eliminar", Vector2(r1.position.x + 36, r1.get_center().y + 13), 36, Color.WHITE)
	elif overlay == "delconfirm":
		var who := ""
		if del_ids.size() == 1:
			var gg := _group_of(String(del_ids[0]))
			who = String(gg.get("title", ""))
		else:
			who = T("%d canciones") % del_ids.size()
		_text(_fit(who, panel.size.x - 80, 38), Vector2(panel.position.x + 40, panel.position.y + 160), 38, ink)
		_text("Se borran con todas sus dificultades", Vector2(panel.position.x + 40, panel.position.y + 225), 28, _ink_soft())
		_text("y todos sus récords. No se puede deshacer.", Vector2(panel.position.x + 40, panel.position.y + 270), 28, _ink_soft())
		var exd: Dictionary = lay.extra
		_button(exd["cancel"], "Cancelar", pcol("button"))
		_button(exd["ok"], "Eliminar", pcol("danger"))
	elif overlay == "addto":
		if not current_song.is_empty():
			_text(_fit("%s · %s" % [current_song.get("title", ""), current_song.get("version", "")], panel.size.x - 80, 26), Vector2(panel.position.x + 40, panel.position.y + 124), 26, _ink_soft())
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
		_button(ex["close"], "Listo", pcol("button"))
		if playlists.size() > 6:
			_text("Solo se muestran las 6 primeras listas.", Vector2(panel.position.x + 40, panel.end.y - 125), 22, _ink_soft())
	else:
		var ex2: Dictionary = lay.extra
		var er: Rect2 = ex2["edit"]
		name_edit.position = er.position
		name_edit.size = er.size
		_button(ex2["cancel"], "Cancelar", pcol("button"))
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
	elif overlay == "diffs":
		var gd3 := _group_of(String(current_song.get("set_id", "")))
		for i in lay.rows.size():
			if lay.rows[i].has_point(pos):
				var chosen: Dictionary = gd3.entries[i]
				overlay = ""
				if _ref(chosen) != _ref(current_song):
					_select_song(chosen)
				return
		if not panel.has_point(pos):
			overlay = ""
	elif overlay == "songmenu":
		if lay.rows[0].has_point(pos):
			sel_mode = true
			sel_ids = {String(menu_group.id): true}
			overlay = ""
		elif lay.rows[1].has_point(pos):
			_ask_delete([String(menu_group.id)])
		elif not panel.has_point(pos):
			overlay = ""
	elif overlay == "delconfirm":
		if ex["ok"].has_point(pos):
			_delete_songs(del_ids)
		elif ex["cancel"].has_point(pos) or not panel.has_point(pos):
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
		press_ms = Time.get_ticks_msec()
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
	if sel_mode:
		if _sel_cancel_rect().has_point(pos):
			_exit_select()
		elif _sel_delete_rect().has_point(pos):
			_ask_delete(sel_ids.keys())
		else:
			var gs := _card_at(pos)
			if _deletable(gs):
				var sid2 := String(gs.id)
				if sel_ids.has(sid2):
					sel_ids.erase(sid2)
				else:
					sel_ids[sid2] = true
		return
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
		if g.entries.size() == 1 and g.get("in_playlist", false):
			_select_song(g.entries[0])
		else:
			_ensure_group_stars(g)
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
		if e.is_empty() or inf != (game_mode == 1):
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

func _last_entry() -> Dictionary:
	var k := "_inf" if game_mode == 1 else ""
	return _find_entry(String(last_played.get("id" + k, "")), String(last_played.get("version" + k, "")))

func _home_tap(pos: Vector2) -> void:
	pos.y -= top_inset
	var x := 55.0
	var cw := viewport_size.x - 110.0
	var le := _last_entry()
	if not le.is_empty() and (Rect2(0, -top_inset, viewport_size.x, 620.0 + top_inset).has_point(pos) or Rect2(viewport_size.x / 2.0 - 220.0, 770, 440, 100).has_point(pos)):
		_select_song(le)
		return
	var n := mini(_home_row_count(), home_records.size())
	for i in n:
		if Rect2(x, HOME_ROWS_Y + i * HOME_ROW_STEP, cw, HOME_ROW_H).has_point(pos):
			var rec: Dictionary = home_records[i]
			_select_song(rec.entry)
			return

func _draw_home() -> void:
	if home_dirty:
		_rebuild_home()
	var w := viewport_size.x
	var x := 55.0
	var cw := w - 110.0
	var muted := pcol("muted")
	var ink := pcol("ink")
	var navy := pcol("bg")
	var le := _last_entry()
	var hero_h := 620.0 + top_inset
	# Imagen de la última canción (horizontal) ocupando la parte de arriba.
	if le.is_empty():
		draw_rect(Rect2(0, 0, w, hero_h), pcol("bg").lerp(pcol("accent"), 0.2))
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
	draw_string(_font(), title_pos, "TILES FOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, pcol("text"))
	draw_set_transform(Vector2(0, top_inset))
	if le.is_empty():
		_text_centered("Aún no has jugado ninguna canción", w / 2, 690, 40, Color.WHITE)
		_text_centered("Elígela en la pestaña Música.", w / 2, 740, 28, muted)
	else:
		_text_centered(_fit(String(le.title), w - 100, 52), w / 2, 690, 52, Color.WHITE)
		_text_centered(_fit("%s · %s" % [T(le.artist), le.version], w - 100, 28), w / 2, 738, 28, muted)
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
		_text(_fit("Juega una canción para guardar tu récord en este modo.", cw, 28), Vector2(55, HOME_ROWS_Y + 55), 28, muted)
	var n := mini(_home_row_count(), home_records.size())
	for i in n:
		var rec: Dictionary = home_records[i]
		var e: Dictionary = rec.entry
		var b: Dictionary = rec.b
		var y := HOME_ROWS_Y + i * HOME_ROW_STEP
		_panel(Rect2(x, y, cw, HOME_ROW_H), pcol("card"), 24)
		if rec.inf:
			_panel(Rect2(x, y, 110, HOME_ROW_H), pcol("violet"), 24)
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
		var sub := "%s · %s" % [e.version, T(DIFFICULTY_LEVELS[int(rec.level)].name)]
		if rec.inf:
			sub += " · " + T("Infinito")
		_text(_fit(sub, cw - 135 - 230, 23), Vector2(x + 135, y + 92), 23, _ink_soft())
		var score_txt := str(int(b.get("score", 0)))
		var sw := _font().get_string_size(score_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
		_text(score_txt, Vector2(x + cw - 28 - sw, y + 74), 36, pcol("accent").darkened(0.2))
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
	var muted := pcol("muted")
	var panel_col := acol(pcol("panel"), 0.92)
	var accent := pcol("accent")
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
	_text(_fit(shown_dir, cw - 80, 24), Vector2(x + 40, 675), 24, _ok() if library_dir != "" else muted)
	_text(_fit("Deja tus .osz en \"Por importar\" y pulsa Recargar.", cw - 80, 24), Vector2(x + 40, 720), 24, muted)
	_text(_fit("Al reinstalar la app, Recargar restaura lo de \"Importadas\".", cw - 80, 24), Vector2(x + 40, 760), 24, muted)
	_button(Rect2(x + 40, 810, half, 100), "Elegir carpeta", pcol("button"))
	_button(Rect2(x + 80 + half, 810, half, 100), "Recargando..." if syncing else "Recargar mapas", accent)
	_panel(Rect2(x, 1000, cw, 330), panel_col, 34)
	_text("Exportar canciones", Vector2(x + 40, 1085), 40, Color.WHITE)
	var n_songs := 0
	for g in groups:
		if g.id != "demo":
			n_songs += 1
	_text(_fit(T("Guarda un .osz de cada canción en \"Importadas\" (%d en la biblioteca).") % n_songs, cw - 80, 24), Vector2(x + 40, 1135), 24, muted)
	_text(_fit("Así no las pierdes si desinstalas la app.", cw - 80, 24), Vector2(x + 40, 1175), 24, muted)
	_button(Rect2(x + 40, 1200, cw - 80, 100), "Exportando..." if syncing else "Exportar canciones", accent)
	_text(_fit(T("Récords, listas y favoritas se guardan en %s dentro de la carpeta.") % PROGRESS_FILE, cw, 22), Vector2(55, 1375), 22, muted)
	_text(_fit("Los mapas importados antes de los fondos hay que importarlos otra vez.", cw, 22), Vector2(55, 1415), 22, muted)
	if status_time > 0.0:
		_text(_fit(status_text, cw, 26), Vector2(55, 1460), 26, _err() if status_error else _ok())
	draw_set_transform(Vector2.ZERO)

# --- Música ----------------------------------------------------------------------

## Una tarjeta de canción. kind: song (corazón), remove (quitar de lista), playlist, plain.
func _draw_card(g: Dictionary, x: float, y: float, w: float, kind: String) -> void:
	if sel_mode and sel_ids.has(g.id):
		_panel(Rect2(x - 7, y - 7, w + 14, CARD_H + 14), pcol("accent"), 33)
	_panel(Rect2(x, y, w, CARD_H), pcol("card"), 28)
	var ink := pcol("ink")
	var soft := _ink_soft()
	var text_w := w - 190 - 150
	if kind == "playlist":
		draw_rect(Rect2(x, y, 190, CARD_H), pcol("violet"))
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
		draw_rect(Rect2(x, y + CARD_H - 46, 190, 46), Color(0, 0, 0, 0.55))
		_text_centered(T("%d dif.") % count, x + 95, y + CARD_H - 13, 28, Color.WHITE)
	else:
		draw_rect(Rect2(x, y, 190, CARD_H), _badge_color(first))
		_text_centered(first.badge, x + 95, y + CARD_H / 2 - 2, 44, Color.WHITE)
		_text_centered(T("%d dif.") % count, x + 95, y + CARD_H / 2 + 44, 28, Color(1, 1, 1, 0.9))
	_text(_fit(g.title, text_w, 38), Vector2(x + 215, y + 82), 38, ink)
	var sub: String = (T("%s · %d dificultades") % [T(g.artist), count]) if count > 1 else ("%s · %s" % [T(g.artist), first.version])
	_text(_fit(sub, text_w, 27), Vector2(x + 215, y + 132), 27, soft)
	if kind == "song" and sel_mode:
		var bc := Vector2(x + w - 66, y + CARD_H / 2.0)
		if g.id == "demo":
			pass
		elif sel_ids.has(g.id):
			draw_circle(bc, 32.0, pcol("accent"))
			draw_polyline(PackedVector2Array([bc + Vector2(-14, 0), bc + Vector2(-4, 12), bc + Vector2(16, -12)]), Color.WHITE, 7.0)
		else:
			draw_arc(bc, 30.0, 0, TAU, 32, Color(0.75, 0.8, 0.88), 6.0, true)
	elif kind == "song":
		_draw_heart(Vector2(x + w - 66, y + CARD_H / 2 - 8), 36.0, pcol("fav") if favorites.has(g.id) else Color(0.8, 0.85, 0.91))
	elif kind == "remove":
		var c := Vector2(x + w - 66, y + CARD_H / 2.0)
		draw_line(c + Vector2(-16, -16), c + Vector2(16, 16), Color(0.85, 0.45, 0.5), 8.0)
		draw_line(c + Vector2(-16, 16), c + Vector2(16, -16), Color(0.85, 0.45, 0.5), 8.0)
	else:
		var pc := Vector2(x + w - 62, y + CARD_H / 2.0)
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-14, -22), pc + Vector2(-14, 22), pc + Vector2(22, 0)]), pcol("accent"))

func _draw_music() -> void:
	var muted := pcol("muted")
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
		var empty_msg := T("Sin resultados para \"%s\"") % search_query
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
	if sel_mode:
		title = T("%d seleccionadas") % sel_ids.size()
	_text(_fit(title, viewport_size.x - 380, 58), Vector2(55, 105), 58, Color.WHITE)
	var dark := pcol("button")
	if sel_mode:
		_button(Rect2(viewport_size.x - 590, 150, 270, 95), "Eliminar", pcol("danger"))
		_button(Rect2(viewport_size.x - 300, 150, 245, 95), "Cancelar", dark)
	elif search_open:
		_button(Rect2(viewport_size.x - 300, 150, 245, 95), "Cerrar", pcol("button"))
	else:
		_button(Rect2(viewport_size.x - 300, 40, 245, 80), "Buscar", dark)
		_button(Rect2(55, 150, 130, 95), "Todas", pcol("accent") if music_tab == 0 else dark)
		_button(Rect2(195, 150, 205, 95), "Favoritas", pcol("fav") if music_tab == 1 else dark)
		_button(Rect2(410, 150, 160, 95), "Listas", pcol("violet") if music_tab == 2 else dark)
		if music_tab != 2:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), T("Orden: %s") % T(SORT_MODES[sort_mode]), dark)
		elif open_playlist < 0:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), "+ Nueva lista", pcol("accent"))
		else:
			_button(Rect2(viewport_size.x - 440, 150, 385, 95), "¿Seguro?" if delete_armed else "Eliminar lista", pcol("danger") if delete_armed else dark)
	draw_set_transform(Vector2.ZERO)
	if status_time > 0.0:
		_text(_fit(status_text, viewport_size.x - 110, 26), Vector2(55, 272 + top_inset), 26, _err() if status_error else _ok())

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
	_stop_ambient()
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
		_cache_stars(entry, parsed)
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
	var pbg := String(entry.get("bg_path", ""))
	prep_tex = OsuImporter.load_image(pbg, 1280) if pbg != "" else null
	_stop_ambient()
	_ambient_play(audio_stream, true)

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
	game_mode = clampi(int(cfg.get_value("mods", "game_mode", 1 if bool(cfg.get_value("mods", "infinite", false)) else 0)), 0, 1)
	mod_x2 = bool(cfg.get_value("mods", "x2", false))
	mod_nofail = bool(cfg.get_value("mods", "nofail", false))
	mod_perfect = bool(cfg.get_value("mods", "perfect", false))
	mod_spectator = bool(cfg.get_value("mods", "spectator", false))
	mod_hardcore = bool(cfg.get_value("mods", "hardcore", false))
	diff_level = clampi(int(cfg.get_value("mods", "diff", 1)), 0, DIFFICULTY_LEVELS.size() - 1)
	library_dir = String(cfg.get_value("library", "dir", ""))
	lives_setting = clampi(int(cfg.get_value("mods", "lives", 3)), LIVES_MIN, LIVES_MAX)
	show_thumbs = bool(cfg.get_value("display", "show_thumbs", true))
	sfx_on = bool(cfg.get_value("display", "sfx", true))
	amb_enabled = bool(cfg.get_value("display", "amb", true))
	note_len = clampf(float(cfg.get_value("display", "note_len", 1.0)), 0.5, 1.5)
	music_vol = clampf(float(cfg.get_value("display", "music_vol", 1.0)), 0.0, 1.0)
	sfx_vol = clampf(float(cfg.get_value("display", "sfx_vol", 1.0)), 0.0, 1.0)
	_apply_volumes()
	var fav_list = cfg.get_value("library", "favorites", [])
	if fav_list is Array:
		for fid in fav_list:
			favorites[String(fid)] = true
	sort_mode = clampi(int(cfg.get_value("library", "sort", 0)), 0, SORT_MODES.size() - 1)
	last_played = {
		"id": String(cfg.get_value("library", "last_id", "")), "version": String(cfg.get_value("library", "last_version", "")),
		"id_inf": String(cfg.get_value("library", "last_id_inf", "")), "version_inf": String(cfg.get_value("library", "last_version_inf", "")),
	}
	var pl = cfg.get_value("library", "playlists", [])
	if pl is Array:
		for p in pl:
			if p is Dictionary and p.has("name") and p.get("refs") is Array:
				playlists.append({"name": String(p.name), "refs": (p.refs as Array).duplicate()})
	show_bg = bool(cfg.get_value("display", "show_bg", true))
	var saved_lang := String(cfg.get_value("display", "lang", lang))
	if saved_lang == "es" or saved_lang == "en":
		lang = saved_lang
	if cfg.has_section("palette"):
		for pk in cfg.get_section_keys("palette"):
			if pal.has(pk):
				pal[pk] = Color.from_string(String(cfg.get_value("palette", pk)), pal[pk])
	bg_vis = clampf(float(cfg.get_value("display", "bg_vis", 0.30)), 0.1, 0.7)
	var sc = cfg.get_value("library", "stars", {})
	if int(cfg.get_value("library", "stars_v", 0)) != STAR_CACHE_VERSION:
		sc = {}   # escala distinta: se recalculan las categorías
	if sc is Dictionary:
		star_cache = (sc as Dictionary).duplicate()
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
	cfg.set_value("mods", "game_mode", game_mode)
	cfg.set_value("mods", "x2", mod_x2)
	cfg.set_value("mods", "nofail", mod_nofail)
	cfg.set_value("mods", "perfect", mod_perfect)
	cfg.set_value("mods", "spectator", mod_spectator)
	cfg.set_value("mods", "hardcore", mod_hardcore)
	cfg.set_value("mods", "diff", diff_level)
	cfg.set_value("library", "dir", library_dir)
	cfg.set_value("mods", "lives", lives_setting)
	cfg.set_value("display", "show_thumbs", show_thumbs)
	cfg.set_value("display", "sfx", sfx_on)
	cfg.set_value("display", "amb", amb_enabled)
	cfg.set_value("display", "note_len", note_len)
	cfg.set_value("display", "music_vol", music_vol)
	cfg.set_value("display", "sfx_vol", sfx_vol)
	cfg.set_value("library", "favorites", favorites.keys())
	cfg.set_value("library", "sort", sort_mode)
	cfg.set_value("library", "last_id", String(last_played.get("id", "")))
	cfg.set_value("library", "last_version", String(last_played.get("version", "")))
	cfg.set_value("library", "last_id_inf", String(last_played.get("id_inf", "")))
	cfg.set_value("library", "last_version_inf", String(last_played.get("version_inf", "")))
	cfg.set_value("library", "playlists", playlists)
	cfg.set_value("display", "show_bg", show_bg)
	cfg.set_value("display", "lang", lang)
	cfg.set_value("library", "stars", star_cache)
	cfg.set_value("library", "stars_v", STAR_CACHE_VERSION)
	for pk in pal:
		cfg.set_value("palette", pk, (pal[pk] as Color).to_html(false))
	cfg.set_value("display", "bg_vis", bg_vis)
	for key in bests:
		cfg.set_value("best", key, bests[key])
	cfg.save(SETTINGS_PATH)

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
	score = roundi(score * run_mult)
	if failed or spectating:   # las partidas perdidas y las del espectador no guardan récord
		run_record = false
		return
	var key := _song_key(current_song)
	var old: Dictionary = bests.get(key, {})
	run_record = score > int(old.get("score", 0))
	if run_record or old.is_empty():
		bests[key] = {"score": score, "rank": maxi(run_rank, int(old.get("rank", 0))), "acc": run_accuracy, "pf": perfects, "gr": greats, "gd": goods, "ms": misses + empties, "mods": _mods_text()}
	elif run_rank > int(old.get("rank", 0)):
		old["rank"] = run_rank
		bests[key] = old
	_save_settings()

func _text_centered(value: String, center_x: float, y: float, size: int, color: Color) -> void:
	value = T(value)
	var width := _font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(value, Vector2(center_x - width / 2, y), size, color)

# --- Pausa / audio -------------------------------------------------------

func _set_paused(value: bool) -> void:
	paused = value
	_kill_fade()
	if value:
		player.volume_db = 0.0
		player.stream_paused = true
	else:
		# Al reanudar el volumen vuelve suave (evita un golpe seco).
		player.stream_paused = false
		player.volume_db = -18.0
		fade_tween = create_tween()
		fade_tween.tween_property(player, "volume_db", 0.0, 0.15)

# --- Música de fondo ------------------------------------------------------
# Al abrir la app suena, baja y apagada (filtro de graves), tu última canción jugada.
# Se detiene al elegir una canción o empezar una partida.

func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var bi := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bi, bus_name)
			AudioServer.set_bus_send(bi, "Master")
	_apply_volumes()

func _vol_db(v: float) -> float:
	return -80.0 if v <= 0.001 else linear_to_db(v)

func _apply_volumes() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, _vol_db(music_vol))
	if si >= 0:
		AudioServer.set_bus_volume_db(si, _vol_db(sfx_vol))

func _adjust_note_len(delta: float) -> void:
	note_len = snappedf(clampf(note_len + delta, 0.5, 1.5), 0.1)
	_save_settings()

func _adjust_music_vol(delta: float) -> void:
	music_vol = snappedf(clampf(music_vol + delta, 0.0, 1.0), 0.1)
	_apply_volumes()
	_save_settings()

func _adjust_sfx_vol(delta: float) -> void:
	sfx_vol = snappedf(clampf(sfx_vol + delta, 0.0, 1.0), 0.1)
	_apply_volumes()
	_save_settings()
	_play_sfx(sfx_life)   # muestra el nuevo volumen

## Música de menú: vuelve sola al salir de Preparar, de la partida o de los resultados.
func _ambient_tick(delta: float) -> void:
	var menu := screen == Screen.LIBRARY or screen == Screen.SETTINGS or screen == Screen.PALETTE
	if not menu or not amb_enabled or previewing:
		if amb_on and not amb_song and not amb_enabled:
			_stop_ambient()
		return
	if amb_on:
		return
	amb_retry -= delta
	if amb_retry <= 0.0:
		amb_retry = 1.0
		_start_ambient()

func _setup_ambient() -> void:
	if AudioServer.get_bus_index("Ambient") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Ambient")
		AudioServer.set_bus_send(bi, "Music")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 1800.0
		AudioServer.add_bus_effect(bi, lp)
	amb_player = AudioStreamPlayer.new()
	amb_player.bus = "Ambient"
	amb_player.volume_db = -60.0
	amb_player.finished.connect(_ambient_loop.bind(amb_player))
	add_child(amb_player)
	amb_player2 = AudioStreamPlayer.new()
	amb_player2.bus = "Ambient"
	amb_player2.volume_db = -60.0
	amb_player2.finished.connect(_ambient_loop.bind(amb_player2))
	add_child(amb_player2)

func _ambient_entry() -> Dictionary:
	var e := _last_entry()
	if e.is_empty() or not e.has("audio_path"):
		e = {}
		for k in ["", "_inf"]:
			var cand := _find_entry(String(last_played.get("id" + k, "")), String(last_played.get("version" + k, "")))
			if not cand.is_empty() and cand.has("audio_path"):
				e = cand
				break
	return e

func _start_ambient() -> void:
	if not amb_enabled:
		return
	var e := _ambient_entry()
	if e.is_empty():
		return
	var stream: AudioStream = OsuImporter.load_audio(String(e.audio_path))
	if stream == null:
		return
	_ambient_play(stream, false)

## Suena suave y tapada (canal "Ambient"). Si ya sonaba otra, hace un fundido cruzado:
## la anterior baja mientras la nueva sube, sin cortes.
func _ambient_play(stream: AudioStream, from_song: bool) -> void:
	if stream == null or amb_player == null or not amb_enabled:
		return
	var old := amb_cur
	var nw := amb_player2 if amb_cur == amb_player else amb_player
	nw.stream = stream
	nw.volume_db = -60.0
	amb_on = true
	amb_song = from_song
	var start := 0.0
	if stream.get_length() > 20.0:
		start = stream.get_length() * 0.25
	nw.play(start)
	amb_cur = nw
	_amb_fade(nw, -17.0, 2.2, false)
	if old != null and old.playing:
		_amb_fade(old, -60.0, 2.2, true)

func _amb_fade(p: AudioStreamPlayer, to_db: float, dur: float, stop_after: bool) -> void:
	var prev = amb_tweens.get(p, null)
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := create_tween()
	amb_tweens[p] = tw
	tw.tween_property(p, "volume_db", to_db, dur)
	if stop_after:
		tw.tween_callback(p.stop)

func _ambient_loop(p: AudioStreamPlayer) -> void:
	if amb_on and p == amb_cur:
		p.play(0.0)

func _stop_ambient() -> void:
	if not amb_on:
		return
	amb_on = false
	amb_song = false
	amb_retry = 0.0
	if amb_cur != null:
		_amb_fade(amb_cur, -60.0, 0.6, true)

func _kill_fade() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	fade_tween = null

## Perder una vida: el volumen baja en 0.3 s y luego se pausa el audio. La partida queda
## congelada al instante; solo el sonido se apaga con suavidad. No toca el tono.
func _pause_with_fade() -> void:
	paused = true
	_kill_fade()
	fade_tween = create_tween()
	fade_tween.tween_property(player, "volume_db", -40.0, 0.3)
	fade_tween.tween_callback(_pause_stream_if_paused)

func _pause_stream_if_paused() -> void:
	if paused:
		player.stream_paused = true

## Perder del todo: la canción se frena y se apaga como un disco que se detiene.
func _fade_slow(duration: float) -> void:
	_kill_fade()
	fade_tween = create_tween().set_parallel(true)
	fade_tween.tween_property(player, "pitch_scale", 0.35, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_tween.tween_property(player, "volume_db", -32.0, duration)

## Final de la canción: desvanecimiento suave.
func _fade_out(duration: float) -> void:
	_kill_fade()
	fade_tween = create_tween()
	fade_tween.tween_property(player, "volume_db", -40.0, duration)

func _stop_audio() -> void:
	previewing = false
	_kill_fade()
	player.stop()
	player.stream_paused = false
	player.volume_db = 0.0
	player.pitch_scale = 1.0
	audio_started = false

# --- Efectos de sonido (generados por código, sin archivos) --------------

func _play_sfx(stream: AudioStreamWAV) -> void:
	if not sfx_on or sfx_player == null or stream == null:
		return
	sfx_player.stream = stream
	sfx_player.play()

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = data
	return wav

## Derrota: tono que cae de agudo a grave con un golpe grave al inicio.
func _gen_fail() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.9
	var n := int(rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		var f := 420.0 * pow(0.16, k)
		ph += TAU * f / rate
		var env := pow(1.0 - k, 1.6) * minf(1.0, t * 80.0)
		var thud := sin(TAU * 55.0 * t) * exp(-t * 9.0) * 0.6
		out[i] = (sin(ph) * 0.6 + sin(ph * 2.0) * 0.18 + thud) * env * 0.85
	return _make_wav(out)

## Perder una vida: golpe corto y seco.
func _gen_life() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.28
	var n := int(rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var k := t / dur
		var f := 320.0 * pow(0.38, k)
		ph += TAU * f / rate
		var env := pow(1.0 - k, 2.0)
		var click := (randf() * 2.0 - 1.0) * exp(-t * 45.0) * 0.3
		out[i] = (sin(ph) * 0.75 + click) * env * 0.9
	return _make_wav(out)

## Escuchar solo el audio de la canción abierta (sin jugar).
func _toggle_preview() -> void:
	if previewing:
		# La canción sin filtro baja suave mientras vuelve el sonido tapado de fondo.
		previewing = false
		_kill_fade()
		fade_tween = create_tween()
		fade_tween.tween_property(player, "volume_db", -40.0, 0.6)
		fade_tween.tween_callback(_stop_audio)
		_ambient_play(audio_stream, true)
		return
	if audio_stream == null:
		return
	_stop_ambient()
	player.stream = audio_stream
	player.pitch_scale = 1.0
	player.stream_paused = false
	player.volume_db = -40.0
	player.play()   # desde el principio, sin filtro, con entrada suave
	previewing = true
	_kill_fade()
	fade_tween = create_tween()
	fade_tween.tween_property(player, "volume_db", 0.0, 0.8)

## Reinicia la canción desde el principio con los mismos ajustes.
func _restart_run() -> void:
	if infinite_run and screen == Screen.GAME and not finished:
		_store_infinite_best()
	life_menu = false
	_start_game()

## Sale de la partida y vuelve a "preparar" de la misma canción (no a la lista).
func _go_prepare() -> void:
	if infinite_run and screen == Screen.GAME and not finished:
		_store_infinite_best()
	_stop_audio()
	paused = false
	life_menu = false
	resume_pending = false
	overlay = ""
	screen = Screen.PREPARE
	_stop_ambient()
	_ambient_play(audio_stream, true)

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
	value = T(value)
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
	elif screen == Screen.PALETTE: _draw_palette()
	else: _draw_results()
	draw_set_transform(Vector2.ZERO)
	if overlay != "" and (screen == Screen.LIBRARY or screen == Screen.PREPARE):
		_draw_overlay()

func _draw_game() -> void:
	var lane_w := viewport_size.x / LANES
	# Fondo base: azul claro; con las 3 estrellas pasa a un verde menta suave (y se queda en las coronas).
	var base_col := pcol("field").lerp(Color(0.78, 0.92, 0.82), bg_blend)
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
			draw_rect(Rect2(note.lane * lane_w + 2, gb - gh, lane_w - 4, gh), Color(0.42, 0.47, 0.55, 0.6))
			continue
		if note.done or (note.type == "start" and started): continue
		var bottom: float = viewport_size.y if note.type == "start" and not started else hit_y - (note.time - song_time) * speed
		var height: float = note.height
		if note.type == "hold":
			height = maxf(lane_w * 0.83 + 90.0, note.duration * speed)
		var rect := Rect2(note.lane * lane_w + 2, bottom - height, lane_w - 4, height)
		if note.type == "hold":
			# Misma silueta cayendo y sosteniendo: solo cambia la intensidad.
			_draw_hold_tile(rect, note.holding, _hold_y(note) if note.holding else hit_y)
		else:
			draw_rect(rect, pcol("tile"))
		if resume_pending and i in resume_idxs and not note.holding:
			draw_rect(rect, Color.WHITE, false, 6.0)
			_text("Continuar", Vector2(rect.position.x + 18, rect.get_center().y + 12), 35, Color.WHITE)
		if note.type == "start": _text("Comenzar", Vector2(rect.position.x+18,rect.get_center().y+12), 35, Color.WHITE)
	for d in dying:
		var p: float = clampf(float(d.t) / DIE_TIME, 0.0, 1.0)
		if d.get("kind", "") == "hold":
			var hb: float = hit_y - (float(d.time) - song_time) * speed
			var hr := Rect2(int(d.lane) * lane_w + 2, hb - float(d.height), lane_w - 4, float(d.height))
			draw_rect(hr, acol(pcol("hold").lerp(pcol("tile"), 0.45), 0.85))
			continue
		var dbottom: float = hit_y - (float(d.time) - song_time) * speed
		var dr := Rect2(int(d.lane) * lane_w + 2, dbottom - float(d.height), lane_w - 4, float(d.height))
		var tc := acol(pcol("tile"), 1.0 - 0.6 * p)
		var hs := dr.size * p
		var ho := (dr.size - hs) / 2.0
		draw_rect(Rect2(dr.position, Vector2(dr.size.x, ho.y)), tc)
		draw_rect(Rect2(dr.position + Vector2(0, ho.y + hs.y), Vector2(dr.size.x, ho.y)), tc)
		draw_rect(Rect2(dr.position + Vector2(0, ho.y), Vector2(ho.x, hs.y)), tc)
		draw_rect(Rect2(dr.position + Vector2(ho.x + hs.x, ho.y), Vector2(ho.x, hs.y)), tc)
		draw_rect(Rect2(dr.position + ho, hs), Color(1, 1, 1, 0.45 * (1.0 - p)), false, 4.0)
	for m in marks:
		var fa: float = 0.35 + 0.65 * (1.0 - clampf(float(m.t) / MARK_TIME, 0.0, 1.0))
		var mc := pcol("miss")
		draw_circle(m.pos, 95.0, acol(mc, 0.28 * fa))
		draw_circle(m.pos, 60.0, acol(mc, 0.50 * fa))
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
		elif combo >= 50: ccol = pcol("gold")
		elif combo >= 25: ccol = Color(0.55, 0.95, 1.0)
		var csize := int(100 + 40 * clampf(combo_pop / 0.18, 0.0, 1.0))
		_text_outlined(str(combo), viewport_size.x / 2, 200 + top_inset, csize, ccol, Color(0.04, 0.16, 0.32, 0.95), 16)
		_text_outlined("COMBO", viewport_size.x / 2, 255 + top_inset, 30, Color.WHITE, Color(0.04, 0.16, 0.32, 0.95), 8)
	_button(Rect2(viewport_size.x-145,35+top_inset,110,100), "II", Color(0.06,0.12,0.2,0.72))
	if game_mode == 0 and not spectating:
		# Barra fina y discreta: pista translúcida y relleno suave que solo se enrojece al quedar poca vida.
		var hb := Rect2(55, 74 + top_inset, viewport_size.x - 55 - 190, 10)
		draw_rect(hb, Color(0.04, 0.16, 0.32, 0.35))
		var hcol := Color(1.0, 1.0, 1.0, 0.85).lerp(Color(1.0, 0.38, 0.38, 0.9), clampf((0.35 - health) / 0.35, 0.0, 1.0))
		if _mod_on("nofail"):
			hcol = Color(0.55, 0.65, 0.8, 0.7)
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * clampf(health, 0.0, 1.0), hb.size.y)), hcol)
	if spectating:
		_text_centered("ESPECTADOR", viewport_size.x / 2.0, 90 + top_inset, 30, Color(1, 1, 1, 0.7))
	if run_lives == LIVES_MIN:
		_draw_lives_bars(55, 60 + top_inset, 64, 16, 12)
	elif run_lives > LIVES_MIN:
		_text_outlined(str(lives_left), 90, 105 + top_inset, 60, _hot(), Color(0.04, 0.16, 0.32, 0.95), 10)
	if infinite_run:
		var ltxt := T("Vuelta %d · x%.1f") % [lap, lap_factor]
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
	draw_rect(Rect2(0, top_inset, viewport_size.x * prog, 10), pcol("accent"))
	if failed and finished:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.6))
		_text_outlined(fail_text, viewport_size.x / 2, viewport_size.y / 2, 90, _hot(), Color(0.02, 0.05, 0.12, 0.95), 14)
	if life_menu:
		var lk := 0.45 if life_menu_lock > 0.0 else 1.0
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.74))
		draw_set_transform(Vector2(0, ui_off))
		_text_outlined("PERDISTE UNA VIDA", viewport_size.x / 2, 520, 62, _hot(), Color(0.02, 0.05, 0.12, 0.95), 12)
		if run_lives == LIVES_MIN:
			_draw_lives_bars(viewport_size.x / 2 - 249.0, 590, 150, 30, 24)
			_text_centered(T("Te quedan %d") % lives_left if lives_left > 0 else "¡Última oportunidad!", viewport_size.x / 2, 700, 34, Color(0.82, 0.91, 1))
		else:
			_text_outlined(str(lives_left), viewport_size.x / 2, 680, 150, _hot(), Color(0.02, 0.05, 0.12, 0.95), 14)
			_text_centered("vidas restantes" if lives_left > 0 else "¡Última oportunidad!", viewport_size.x / 2, 735, 30, Color(0.82, 0.91, 1))
		_button(_menu_btn_rect(0), "RENDIRSE", acol(pcol("danger").darkened(0.25), lk))
		_button(_menu_btn_rect(1), "REINICIAR", acol(pcol("button"), lk))
		_button(_menu_btn_rect(2), "CONTINUAR", acol(pcol("accent"), lk))
		draw_set_transform(Vector2.ZERO)
	elif paused and not resume_pending:
		draw_rect(Rect2(Vector2.ZERO,viewport_size), Color(0,0,0,0.74))
		draw_set_transform(Vector2(0, ui_off))
		_text_centered("PAUSA", viewport_size.x / 2, 690, 62, Color.WHITE)
		_button(_menu_btn_rect(0), "SALIR", pcol("button"))
		_button(_menu_btn_rect(1), "REINICIAR", pcol("button"))
		_button(_menu_btn_rect(2), "CONTINUAR", pcol("accent"))
		draw_set_transform(Vector2.ZERO)

## Tecla larga: degradado (claro arriba, oscuro abajo) con línea y círculo con brillo.
## Al sostenerla mantiene su tamaño y sigue bajando: lo que pasa de la línea de golpeo se
## rellena de un azul más claro con borde curvo hacia arriba (como un dedo) hasta completarla.
func _draw_hold_tile(rect: Rect2, active: bool, line_y: float) -> void:
	var light := pcol("hold").lerp(pcol("nav_home"), 0.35)
	var dark := pcol("tile")
	if active:
		dark = light.lerp(dark, 0.3)
	var cx := rect.get_center().x
	var radius := 34.0
	var head_off := minf(viewport_size.x / LANES * 0.83, maxf(45.0, rect.size.y - 45.0))
	var head := Vector2(cx, rect.end.y - head_off)
	var g_bot := head.y
	if active:
		g_bot = minf(line_y, rect.end.y)
	var fade_len := 640.0
	var g_top := maxf(rect.position.y, g_bot - fade_len)
	if rect.end.y > g_bot:
		draw_rect(Rect2(rect.position.x, g_bot, rect.size.x, rect.end.y - g_bot), dark)
	if g_top > rect.position.y:
		draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, g_top - rect.position.y), light)
	if g_bot > g_top:
		var g_mid := g_bot - (g_bot - g_top) * 0.5
		var mid_col := dark.lerp(light, 0.22)
		var gx := rect.position.x
		var gx2 := rect.end.x
		draw_polygon(PackedVector2Array([Vector2(gx, g_mid), Vector2(gx2, g_mid), Vector2(gx2, g_bot), Vector2(gx, g_bot)]), PackedColorArray([mid_col, mid_col, dark, dark]))
		draw_polygon(PackedVector2Array([Vector2(gx, g_top), Vector2(gx2, g_top), Vector2(gx2, g_mid), Vector2(gx, g_mid)]), PackedColorArray([light, light, mid_col, mid_col]))
	var glow := pcol("hold").lightened(0.3)
	var cap_h := 0.0
	var fill_h := rect.end.y - line_y
	if active and fill_h > 2.0:
		var fill_top := light.lerp(Color.WHITE, 0.4)
		var fill_bot := light.lerp(Color.WHITE, 0.28)
		cap_h = minf(48.0, fill_h)
		var fx := rect.position.x
		var fx2 := rect.end.x
		draw_polygon(PackedVector2Array([Vector2(fx, line_y), Vector2(fx2, line_y), Vector2(fx2, rect.end.y), Vector2(fx, rect.end.y)]), PackedColorArray([fill_top, fill_top, fill_bot, fill_bot]))
		var cap := PackedVector2Array()
		var n := 24
		for k in range(n + 1):
			var u := -1.0 + 2.0 * k / float(n)
			cap.append(Vector2(cx + u * rect.size.x / 2.0, line_y - cap_h * (1.0 - u * u)))
		draw_colored_polygon(cap, fill_top)
		draw_polyline(cap, acol(glow, 0.95), 5.0, true)
	# Línea: tenue arriba, más intensa abajo; termina antes del aro o de la cúpula.
	var line_top := rect.position.y + 30.0
	var line_end := head.y - radius - 8.0
	if active:
		line_end = line_y - cap_h - 8.0
	if line_end > line_top + 10.0:
		var lc := pcol("hold").lightened(0.55)
		var a_bot := 0.95 if active else 0.7
		var hw := 2.5
		draw_polygon(
			PackedVector2Array([Vector2(cx - hw, line_top), Vector2(cx + hw, line_top), Vector2(cx + hw, line_end), Vector2(cx - hw, line_end)]),
			PackedColorArray([acol(lc, 0.12), acol(lc, 0.12), acol(lc, a_bot), acol(lc, a_bot)]))
	if active:
		return
	# Círculo con brillo (solo antes de tocarla).
	for k in 5:
		var rr := radius + 30.0 - k * 6.0
		draw_circle(head, rr, acol(glow, 0.09 * (0.4 + 0.15 * k)))
	draw_circle(head, radius, acol(Color(0, 0.02, 0.05), 0.55))
	draw_arc(head, radius, 0, TAU, 48, acol(glow, 0.9), 6.0, true)
	draw_arc(head, radius - 5.0, 0, TAU, 48, Color(1, 1, 1, 0.55), 2.0, true)

func _draw_difficulty_picker() -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0, 0, 0, 0.62))
	var layout := _picker_layout()
	var panel: Rect2 = layout.panel
	_panel(panel, pcol("card"), 34)
	var inner_w := panel.size.x - 80.0
	_text(_fit(open_group.title, inner_w, 44), Vector2(panel.position.x + 40, panel.position.y + 76), 44, pcol("ink"))
	var sub: String = open_group.artist
	if not String(open_group.creator).is_empty():
		sub += T(" · mapa de %s") % open_group.creator
	_text(_fit(sub, inner_w, 27), Vector2(panel.position.x + 40, panel.position.y + 125), 27, _ink_soft())
	for i in layout.rows.size():
		var r: Rect2 = layout.rows[i]
		var e: Dictionary = open_group.entries[i]
		_panel(r, _soft(), 24)
		var bcol := Color(0.45, 0.52, 0.62)
		var pb: Dictionary = bests.get(_song_key(e), {})
		if not pb.is_empty():
			bcol = RANK_COLORS[int(pb.rank)]
		elif bests.has(_song_key(e) + "|inf"):
			bcol = pcol("violet")
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
		var vw := r.size.x - 180.0
		var st := _stars_of(e)
		if st >= 0.0:
			_draw_star_chip(Rect2(r.end.x - 214.0, r.position.y + 10.0, 204.0, r.size.y - 20.0), st)
			vw -= 214.0
		_text(_fit(e.version, vw, 34), Vector2(r.position.x + 155, r.get_center().y + 12), 34, pcol("ink"))

func _draw_prepare() -> void:
	_background(); draw_set_transform(Vector2(0, ui_off))
	var w := viewport_size.x
	var cx := w / 2.0
	var muted := pcol("muted")
	var gold := pcol("gold")
	_button(Rect2(35, 45, 180, 95), "< Volver", pcol("button"))
	_button(Rect2(235, 45, w - 270, 95), "+ A lista", pcol("violet"))
	# Botón cuadrado de reproducir / detener, a la izquierda del título.
	var pb := Rect2(60, 175, 110, 110)
	var pcolr := pcol("danger") if previewing else pcol("accent")
	if audio_stream == null:
		pcolr = acol(pcol("button"), 0.4)
	_panel(pb, pcolr, 26)
	var pc := pb.get_center()
	if previewing:
		draw_rect(Rect2(pc.x - 17, pc.y - 17, 34, 34), Color.WHITE)
	else:
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-14, -24), pc + Vector2(-14, 24), pc + Vector2(24, 0)]), Color.WHITE)
	var text_w := w - 195.0 - 60.0
	_text(_fit(current_song.title, text_w, 52), Vector2(195, 236), 52, Color.WHITE)
	_text(_fit("%s · %s" % [T(current_song.artist), current_song.version], text_w, 30), Vector2(197, 282), 30, muted)
	# Imagen del mapa, igual que en Inicio (se funde con el fondo).
	var hero := Rect2(0, 320, w, 400)
	if prep_tex != null:
		_draw_cover(prep_tex, hero)
	else:
		draw_rect(hero, _badge_color(current_song).darkened(0.3))
	var navy := pcol("bg")
	var bands := 16
	for k in bands:
		var f := float(k + 1) / bands
		draw_rect(Rect2(0, hero.end.y - 140.0 + k * 140.0 / bands, w, 140.0 / bands + 1.0), Color(navy.r, navy.g, navy.b, 0.98 * pow(f, 1.7)))
		draw_rect(Rect2(0, hero.position.y + k * 50.0 / bands, w, 50.0 / bands + 1.0), Color(navy.r, navy.g, navy.b, 0.9 * (1.0 - f)))
	_draw_diff_pill()
	# Mejor récord de este modo, con los modificadores con que se logró.
	_panel(Rect2(80, 745, w - 160, 250), acol(pcol("panel"), 0.92), 34)
	var key := _song_key(current_song)
	if game_mode == 0:
		var b: Dictionary = bests.get(key, {})
		if b.is_empty():
			_text_centered("Mejor récord: sin récord todavía", cx, 880, 34, muted)
		else:
			var rk := clampi(int(b.get("rank", 0)), 0, RANKS.size() - 1)
			_text_centered(RANKS[rk], 230, 905, 150, RANK_COLORS[rk])
			_text("Mejor récord", Vector2(380, 790), 24, muted)
			_text(str(int(b.get("score", 0))), Vector2(380, 862), 72, Color.WHITE)
			var l1 := T("Precisión %.1f %%") % float(b.get("acc", 0.0))
			if b.has("ms"):
				l1 += " · " + T("Fallos: %d") % int(b.ms)
			_text(_fit(l1, 590, 24), Vector2(380, 900), 24, muted)
			if b.has("pf"):
				_text(_fit("Perfect %d · Great %d · Good %d" % [int(b.pf), int(b.gr), int(b.gd)], 590, 24), Vector2(380, 934), 24, muted)
			var bm := String(b.get("mods", ""))
			_text(_fit(bm if bm != "" else T("Sin modificadores"), 590, 24), Vector2(380, 968), 24, gold)
	else:
		var ib: Dictionary = bests.get(key + "|inf", {})
		if ib.is_empty():
			_text_centered("Mejor récord: sin récord todavía", cx, 880, 34, muted)
		else:
			var n_st := mini(int(ib.get("stars", 0)), 3)
			var n_cr := mini(int(ib.get("crowns", 0)), 3)
			for i in 3:
				_draw_award("star", Vector2(150 + i * 80, 840), 28.0, i < n_st)
				_draw_award("crown", Vector2(150 + i * 80, 925), 26.0, i < n_cr)
			_text("Mejor récord", Vector2(430, 790), 24, muted)
			_text(str(int(ib.get("score", 0))), Vector2(430, 862), 72, Color.WHITE)
			_text(T("Vuelta %d") % int(ib.get("laps", 1)), Vector2(430, 912), 26, muted)
			var im := String(ib.get("mods", ""))
			_text(_fit(im if im != "" else T("Sin modificadores"), 540, 24), Vector2(430, 960), 24, gold)
	# Datos del mapa.
	var info := T("%d notas · %d sostenidas") % [song_stats.notes, song_stats.holds] + " · " + _format_time(song_stats.duration) + " · " + (T("Con audio") if audio_stream != null else T("Sin audio"))
	_text_centered(_fit(info, w - 100, 28), cx, 1040, 28, Color.WHITE if audio_stream != null else Color(1, 0.6, 0.6))
	_button(Rect2(100, 1060, w - 200, 130), "JUGAR", pcol("accent"))
	# Modificadores (abajo del todo).
	_panel(Rect2(80, 1220, w - 160, 660), acol(pcol("panel"), 0.92), 34)
	var mode_name := T("ESTÁNDAR") if game_mode == 0 else "TILES"
	_text(T("MODIFICADORES") + " · " + mode_name, Vector2(130, 1270), 28, muted)
	var lvl: Dictionary = DIFFICULTY_LEVELS[diff_level]
	var demo_song: bool = current_parsed.is_empty()
	_button(Rect2(110, 1295, 150, 90), "-", acol(pcol("button"), 0.4 if demo_song else 1.0))
	_button(Rect2(w - 260, 1295, 150, 90), "+", acol(pcol("button"), 0.4 if demo_song else 1.0))
	_text_centered("Dificultad de notas", cx, 1325, 24, muted)
	_text_centered("—" if demo_song else String(lvl.name), cx, 1375, 44, Color(1, 1, 1, 0.4) if demo_song else lvl.color)
	_button(Rect2(110, 1400, 150, 90), "-", pcol("button"))
	_button(Rect2(w - 260, 1400, 150, 90), "+", pcol("button"))
	_text_centered("Velocidad · AUTO" if speed_auto else "Velocidad · MANUAL (toca: auto)", cx, 1430, 24, muted)
	_text_centered("x%.1f" % _effective_mult(), cx, 1478, 44, pcol("accent").lightened(0.3) if speed_auto else Color.WHITE)
	var ids := _mod_ids()
	for i in ids.size():
		var on := _mod_on(String(ids[i]))
		_button(_mod_rect(i), _mod_label(String(ids[i])), pcol("accent") if on else pcol("button"))
	if game_mode == 1:
		_button(Rect2(130, 1720, 170, 90), "-", pcol("button"))
		_button(Rect2(w - 300, 1720, 170, 90), "+", pcol("button"))
		_text_centered(T("%d vidas") % lives_setting, cx, 1782, 44, Color.WHITE)
	var pm := _mods_mult()
	var pm_text := T("Puntos x%.2f") % pm
	if _mod_on("spectator"):
		pm_text = T("Espectador: no se guarda récord")
	_text_centered(pm_text, cx, 1852, 28, _ok() if pm >= 1.0 else Color(1.0, 0.75, 0.4))

func _lang_rect(i: int) -> Rect2:
	return Rect2(viewport_size.x - 80.0 - 30.0 - 2.0 * 170.0 - 16.0 + i * 186.0, 1125, 170, 90)

func _draw_settings() -> void:
	_background()
	set_scroll = clampf(set_scroll, 0.0, _settings_max_scroll())
	draw_set_transform(Vector2(0, ui_off - set_scroll))
	var w := viewport_size.x
	var muted := pcol("muted")
	var panel_col := acol(pcol("panel"), 0.92)
	var on_col := pcol("accent")
	var off_col := pcol("button")
	_text("AJUSTES", Vector2(55, 105 + top_inset), 58, Color.WHITE)
	_panel(Rect2(80, 330, w - 160, 180), panel_col, 34)
	_text("Fondos de los mapas", Vector2(130, 415), 40, Color.WHITE)
	_text("Imagen del mapa detrás de las teclas", Vector2(130, 465), 26, muted)
	_button(Rect2(w - 330, 375, 200, 90), "SÍ" if show_bg else "NO", on_col if show_bg else off_col)
	var a := 1.0 if show_bg else 0.4
	_panel(Rect2(80, 540, w - 160, 300), acol(pcol("panel"), 0.92 * a), 34)
	_text("Visibilidad del fondo", Vector2(130, 625), 40, Color(1, 1, 1, a))
	_button(Rect2(130, 690, 170, 110), "-", acol(off_col, a))
	_button(Rect2(w - 300, 690, 170, 110), "+", acol(off_col, a))
	_text_centered("%d %%" % roundi(bg_vis * 100.0), w / 2, 765, 56, Color(1, 1, 1, a))
	_panel(Rect2(80, 870, w - 160, 180), panel_col, 34)
	_text("Miniaturas de canciones", Vector2(130, 955), 40, Color.WHITE)
	_text("Imagen del mapa en cada canción de la lista", Vector2(130, 1005), 26, muted)
	_button(Rect2(w - 330, 915, 200, 90), "SÍ" if show_thumbs else "NO", on_col if show_thumbs else off_col)
	_panel(Rect2(80, 1080, w - 160, 180), panel_col, 34)
	_text("Idioma", Vector2(130, 1165), 40, Color.WHITE)
	_text("Idioma de la aplicación", Vector2(130, 1215), 26, muted)
	_button(_lang_rect(0), "Español", on_col if lang == "es" else off_col)
	_button(_lang_rect(1), "English", on_col if lang == "en" else off_col)
	_panel(Rect2(80, 1290, w - 160, 180), panel_col, 34)
	_text("Paleta de colores", Vector2(130, 1375), 40, Color.WHITE)
	_text("Cambia los colores de la app", Vector2(130, 1425), 26, muted)
	_button(Rect2(w - 330, 1335, 200, 90), "Editar", on_col)
	_panel(Rect2(80, 1500, w - 160, 180), panel_col, 34)
	_text("Efectos de sonido", Vector2(130, 1585), 40, Color.WHITE)
	_text("Sonidos al perder y al perder una vida", Vector2(130, 1635), 26, muted)
	_button(Rect2(w - 330, 1545, 200, 90), "SÍ" if sfx_on else "NO", on_col if sfx_on else off_col)
	_panel(Rect2(80, 1710, w - 160, 180), panel_col, 34)
	_text("Música de fondo", Vector2(130, 1795), 40, Color.WHITE)
	_text("Suena en el inicio y los menús", Vector2(130, 1845), 26, muted)
	_button(Rect2(w - 330, 1755, 200, 90), "SÍ" if amb_enabled else "NO", on_col if amb_enabled else off_col)
	_panel(Rect2(80, 1920, w - 160, 300), panel_col, 34)
	_text("Volumen de la música", Vector2(130, 2005), 40, Color.WHITE)
	_button(Rect2(130, 2040, 170, 110), "-", off_col)
	_button(Rect2(w - 300, 2040, 170, 110), "+", off_col)
	_text_centered("%d %%" % roundi(music_vol * 100.0), w / 2, 2115, 56, Color.WHITE)
	_panel(Rect2(80, 2210, w - 160, 300), panel_col, 34)
	_text("Volumen de los efectos", Vector2(130, 2295), 40, Color.WHITE)
	_button(Rect2(130, 2330, 170, 110), "-", off_col)
	_button(Rect2(w - 300, 2330, 170, 110), "+", off_col)
	_text_centered("%d %%" % roundi(sfx_vol * 100.0), w / 2, 2405, 56, Color.WHITE)
	_panel(Rect2(80, 2500, w - 160, 300), panel_col, 34)
	_text("Largo de las notas", Vector2(130, 2585), 40, Color.WHITE)
	_button(Rect2(130, 2620, 170, 110), "-", off_col)
	_button(Rect2(w - 300, 2620, 170, 110), "+", off_col)
	_text_centered("%d %%" % roundi(note_len * 100.0), w / 2, 2695, 56, Color.WHITE)
	if status_time > 0.0:
		_text(_fit(status_text, w - 160, 26), Vector2(80, 270), 26, _err() if status_error else _ok())
	_draw_nav()

## Pantalla de resultados (también al perder): fondo de la canción arriba con borde curvo,
## título, estrellas/coronas (Infinito) o rango (Casual/Vidas), puntaje y mejor, y abajo
## los botones de repetir y de ir a canciones.
func _draw_results_infinite() -> void:
	_draw_results_screen()

func _draw_results() -> void:
	_draw_results_screen()

func _results_curve_y(x: float, base: float) -> float:
	var t := (x - viewport_size.x / 2.0) / (viewport_size.x / 2.0)
	return base + 90.0 * (1.0 - t * t)

func _draw_results_screen() -> void:
	var w := viewport_size.x
	var h := viewport_size.y
	var base := 1100.0
	draw_rect(Rect2(Vector2.ZERO, viewport_size), pcol("bg"))
	if show_bg and bg_texture != null:
		_draw_cover(bg_texture, Rect2(0, 0, w, base + 120.0))
	var cur := PackedVector2Array()
	var steps := 40
	for k in range(steps + 1):
		var x := w * k / float(steps)
		cur.append(Vector2(x, _results_curve_y(x, base)))
	# Zona de arriba oscurecida (se sigue viendo el fondo de la canción).
	var top_poly := PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
	for k in range(steps, -1, -1):
		top_poly.append(cur[k])
	var shade := pcol("bg").darkened(0.35)
	draw_colored_polygon(top_poly, acol(shade, 0.62 if (show_bg and bg_texture != null) else 1.0))
	# Zona de abajo: sólida, con el borde curvo.
	var bot_poly := PackedVector2Array()
	for k in range(steps + 1):
		bot_poly.append(cur[k])
	bot_poly.append(Vector2(w, h))
	bot_poly.append(Vector2(0, h))
	draw_colored_polygon(bot_poly, pcol("bg"))
	draw_set_transform(Vector2(0, ui_off))
	var muted := pcol("muted")
	# Título de la canción.
	var title := String(current_song.get("title", ""))
	var ver := String(current_song.get("version", ""))
	if ver != "":
		title += " · " + ver
	_text_centered(_fit(title, w - 140.0, 44), w / 2, 170 + top_inset, 44, Color.WHITE)
	if failed:
		_text_centered(fail_text, w / 2, 235 + top_inset, 32, _hot())
	elif run_record:
		_text_centered("¡Nuevo récord!", w / 2, 235 + top_inset, 34, Color(1.0, 0.6, 0.1))
	# Estrellas/coronas (Infinito) o rango (Casual y Vidas).
	var cy := 470.0
	if infinite_run:
		for i in 3:
			_draw_award("star", Vector2(w / 2 + (i - 1) * 190.0, cy - 60.0), 70.0, i < stars)
		for i in 3:
			_draw_award("crown", Vector2(w / 2 + (i - 1) * 190.0, cy + 120.0), 62.0, i < crowns)
	else:
		_text_centered(RANKS[run_rank], w / 2, cy + 90.0, 340, RANK_COLORS[run_rank])
	# Puntaje y mejor.
	_text_centered(str(score), w / 2, 840, 190, Color.WHITE)
	var best_txt := ""
	if infinite_run:
		var ib: Dictionary = bests.get(_song_key(current_song) + "|inf", {})
		if not ib.is_empty():
			best_txt = T("Mejor: vuelta %d · %d pts") % [int(ib.get("laps", 1)), int(ib.get("score", 0))]
	else:
		var best: Dictionary = bests.get(_song_key(current_song), {})
		if not best.is_empty():
			best_txt = T("Mejor: %s · %d") % [RANKS[int(best.rank)], int(best.score)]
	if best_txt != "":
		_text_centered(best_txt, w / 2, 910, 42, muted)
	# Detalle pequeño.
	var info := ""
	if infinite_run:
		info = T("Llegaste a la vuelta") + " " + str(lap) + " · " + T("velocidad x%.1f") % lap_factor
	else:
		info = T("Precisión %.1f %%") % run_accuracy + " · Perfect %d · Great %d · Good %d · " % [perfects, greats, goods] + T("Fallos: %d") % misses
	_text_centered(_fit(info, w - 100.0, 28), w / 2, 975 + top_inset * 0.0, 28, muted)
	var mt := _mods_text()
	var note_txt := T("Puntos x%.2f") % run_mult
	if mt != "":
		note_txt = mt + " · " + note_txt
	if spectating:
		note_txt = T("Espectador: no se guarda récord")
	if note_txt != "":
		_text_centered(_fit(note_txt, w - 100.0, 26), w / 2, 1020, 26, muted)
	# Botones: canciones (círculo) a la izquierda y repetir (píldora) al lado.
	var by := 1290.0
	var bh := 150.0
	var ring := _results_songs_rect()
	var retry := _results_retry_rect()
	var bcol := pcol("accent")
	draw_circle(ring.get_center(), bh / 2.0, bcol)
	draw_circle(ring.get_center(), bh / 2.0 - 9.0, pcol("bg"))
	var ic := ring.get_center()
	for k in 3:
		draw_rect(Rect2(ic.x - 32.0, ic.y - 30.0 + k * 26.0, 64.0, 10.0), bcol)
	_panel(retry, bcol, bh / 2.0)
	var rc := retry.get_center()
	draw_arc(rc, 34.0, deg_to_rad(-40.0), deg_to_rad(250.0), 36, Color.WHITE, 11.0, true)
	var tip := rc + Vector2(cos(deg_to_rad(-40.0)), sin(deg_to_rad(-40.0))) * 34.0
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-6, -30), tip + Vector2(34, 4), tip + Vector2(-14, 20)]), Color.WHITE)
	draw_set_transform(Vector2.ZERO)

func _results_songs_rect() -> Rect2:
	return Rect2(70, 1290, 150, 150)

func _results_retry_rect() -> Rect2:
	return Rect2(250, 1290, viewport_size.x - 320, 150)

## Mismo fondo que _background() pero solo dentro de un rectángulo (para tapar la lista bajo la cabecera).
func _background_rect(r: Rect2) -> void:
	draw_rect(r, pcol("bg"))
	var rect_poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var center := Vector2(viewport_size.x * 0.75, viewport_size.y * 0.22)
	for i in range(10):
		var rad := 700.0 - i * 50.0
		var circle := PackedVector2Array()
		for k in 48:
			circle.append(center + Vector2(cos(k * TAU / 48.0), sin(k * TAU / 48.0)) * rad)
		for piece in Geometry2D.intersect_polygons(circle, rect_poly):
			draw_colored_polygon(piece, acol(pcol("accent"), 0.025))

func _background() -> void:
	draw_rect(Rect2(Vector2.ZERO,viewport_size),pcol("bg"))
	if show_bg and bg_texture != null and (screen == Screen.PREPARE or screen == Screen.RESULTS):
		_draw_cover(bg_texture, Rect2(Vector2.ZERO, viewport_size))
		draw_rect(Rect2(Vector2.ZERO, viewport_size), acol(pcol("bg"), 0.82))
	for i in range(10): draw_circle(Vector2(viewport_size.x*0.75,viewport_size.y*0.22),700-i*50,acol(pcol("accent"), 0.025))

func _button(rect: Rect2, label: String, color: Color) -> void:
	label = T(label)
	_panel(rect,color,24); var width := _font().get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,34).x
	_text(label,Vector2(rect.get_center().x-width/2,rect.get_center().y+12),34,Color.WHITE)

func _panel(rect: Rect2, color: Color, radius: float) -> void: draw_style_box(_box(color,radius),rect)
func _box(color: Color, radius: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color=color
	box.corner_radius_top_left=int(radius); box.corner_radius_top_right=int(radius); box.corner_radius_bottom_left=int(radius); box.corner_radius_bottom_right=int(radius)
	return box
func _text_outlined(value: String, center_x: float, y: float, size: int, color: Color, outline_color: Color, outline: int) -> void:
	value = T(value)
	if color.r == 1.0 and color.g == 1.0 and color.b == 1.0:
		var tc := pcol("text")
		color = Color(tc.r, tc.g, tc.b, color.a)
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

func _text(value: String, pos: Vector2, size: int, color: Color) -> void:
	if color.r == 1.0 and color.g == 1.0 and color.b == 1.0:   # blanco = "color de texto" de la paleta
		var tc := pcol("text")
		color = Color(tc.r, tc.g, tc.b, color.a)
	draw_string(_font(), pos, T(value), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

## Texto sin traducir ni cambiar de color (para etiquetas que ya van con su color de contraste).
func _text_fixed(value: String, pos: Vector2, size: int, color: Color) -> void:
	draw_string(_font(), pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
func _font() -> Font: return ThemeDB.fallback_font
