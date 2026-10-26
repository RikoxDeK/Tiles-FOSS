extends CanvasLayer
## Pantalla "Descargar mapas": busca en el mirror y baja .osz.
## Está hecha con controles nativos de Godot (LineEdit, ScrollContainer, Button) para que el
## teclado del móvil y el scroll táctil funcionen sin código extra; los colores salen de la paleta
## de la app y se reconstruye cada vez que se abre, así que respeta los cambios de paleta.
##
## main.gd la abre con open(), escucha osz_ready (ruta del .osz ya descargado), lo importa y
## responde con set_import_result().

signal osz_ready(path: String, set_id: int)

const Downloader = preload("res://scripts/beatmap_downloader.gd")
const MODE_STD := 0
const MODE_MANIA := 3
const MODE_ALL := -1
## Estados de osu! que se pueden filtrar: [código, nombre].
const STATUS_LIST := [[1, "Ranked"], [2, "Approved"], [3, "Qualified"], [4, "Loved"], [0, "Pending"], [-2, "Graveyard"]]

var colors := {}
var top_inset := 0.0
var tr_fn := Callable()

var _dl: Variant = null   # BeatmapDownloader (sin tipo estático: sus métodos son del script)
var _root: ColorRect
var _edit: LineEdit
var _status: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _more_btn: Button
var _mode_btns := {}
var _status_btns := {}
var _video_btn: Button
var _thumbs := {}         # set_id -> TextureRect
var _covers := {}         # set_id -> Texture2D (caché para reconstruir la lista)
var _card_btns := {}      # set_id -> Button
var _states := {}         # set_id -> "queued" | "loading" | "importing" | "done" | "failed" | "error"

var _query := ""
var _mode := MODE_MANIA
var _statuses: Array = [1, 2, 4]   # ranked, approved, loved
var _no_video := true
var _page := 0
var _sets: Array = []
var _loading := false
var _end := false

# Desplazamiento táctil propio: los botones y tarjetas se "comen" el toque y el ScrollContainer
# solo se movía si el dedo caía en un hueco entre canciones. Aquí el arrastre vale en cualquier punto de la lista.
const DRAG_START := 18.0          # píxeles que hay que mover el dedo para que cuente como arrastre y no como toque
var _drag_on := false
var _drag_moved := false          # el gesto actual fue un arrastre: se ignoran los botones al soltar
var _drag_start := Vector2.ZERO
var _vel := 0.0                   # velocidad de la inercia (px/s)
var _fpos := 0.0                  # posición con decimales (scroll_vertical solo admite enteros y se atascaba)
var _drag_ms := 0


func _ready() -> void:
	layer = 60
	visible = false
	_dl = Downloader.new()
	add_child(_dl)
	_dl.search_finished.connect(_on_search)
	_dl.download_progress.connect(_on_progress)
	_dl.download_finished.connect(_on_download)
	_dl.cover_loaded.connect(_on_cover)


func _scroll_max() -> float:
	return maxf(0.0, _list.size.y - _scroll.size.y)


## Mueve la lista con decimales; devuelve true si chocó con un borde.
func _scroll_by(dy: float) -> bool:
	var want := _fpos + dy
	_fpos = clampf(want, 0.0, _scroll_max())
	_scroll.scroll_vertical = roundi(_fpos)
	return not is_equal_approx(want, _fpos)


func _input(event: InputEvent) -> void:
	if not visible or _scroll == null or not is_instance_valid(_scroll):
		return
	var rect := _scroll.get_global_rect()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_vel = 0.0
				_drag_moved = false
				_drag_on = rect.has_point(mb.position)
				_drag_start = mb.position
				_drag_ms = Time.get_ticks_msec()
				_fpos = float(_scroll.scroll_vertical)
			else:
				if _drag_on and _drag_moved and Time.get_ticks_msec() - _drag_ms > 90:
					_vel = 0.0   # soltó el dedo parado: sin inercia
				_drag_on = false
		elif mb.pressed and rect.has_point(mb.position):
			_fpos = float(_scroll.scroll_vertical)
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-140.0)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(140.0)
	elif event is InputEventMouseMotion and _drag_on:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_drag_start) > DRAG_START:
			_drag_moved = true
			_drag_ms = Time.get_ticks_msec()
			if _edit != null:
				_edit.release_focus()
			# El primer tramo (hasta pasar el umbral) también se aplica, para que no "salte" ni se sienta pegajoso.
			_scroll_by(-(mm.position.y - _drag_start.y))
		elif _drag_moved:
			var now := Time.get_ticks_msec()
			var dt := maxf(0.004, float(now - _drag_ms) / 1000.0)
			_drag_ms = now
			_vel = clampf(lerpf(_vel, -mm.relative.y / dt, 0.4), -7000.0, 7000.0)
			_scroll_by(-mm.relative.y)
		if _drag_moved:
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or _scroll == null or _drag_on or absf(_vel) < 12.0:
		return
	if _scroll_by(_vel * delta):
		_vel = 0.0   # tocó un borde
		return
	_vel *= exp(-3.0 * delta)   # igual que en Música y Ajustes


func open(palette: Dictionary, inset: float, translate: Callable) -> void:
	colors = palette
	top_inset = inset
	tr_fn = translate
	_build()
	visible = true
	if _sets.is_empty() and not _loading:
		_search(true)


func close() -> void:
	if _edit != null:
		_edit.release_focus()
	visible = false


## main.gd llama aquí tras intentar importar el .osz descargado.
func set_import_result(set_id: int, result: Dictionary) -> void:
	if result.get("ok", false):
		_states[set_id] = "done"
		_set_status(_t("Importado: %s (%d dificultades)") % [result.get("title", ""), int(result.get("count", 0))], false)
	else:
		_states[set_id] = "failed"
		_set_status(_t(String(result.get("error", "No se pudo importar"))), true)
	_apply_state(set_id)


# ---------------------------------------------------------------------------
# Construcción de la interfaz
# ---------------------------------------------------------------------------

func _c(role: String) -> Color:
	return colors.get(role, Color.WHITE)


func _t(s: String) -> String:
	return tr_fn.call(s) if tr_fn.is_valid() else s


func _style(color: Color, radius: int, margin := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b


func _label(text: String, size: int, color: Color, clip := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if clip:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l


func _btn(text: String, color: Color, size := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _style(color, 24, 12))
	b.add_theme_stylebox_override("disabled", _style(color.darkened(0.45), 24, 12))
	for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(cn, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
	return b


func _build() -> void:
	if _root != null:
		_root.queue_free()
	_card_btns.clear()
	_mode_btns.clear()
	_status_btns.clear()
	_thumbs.clear()
	_more_btn = null

	_root = ColorRect.new()
	_root.color = _c("bg")
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30 + int(top_inset))
	margin.add_theme_constant_override("margin_bottom", 60)
	_root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	margin.add_child(col)

	# Cabecera
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	var back := _btn("‹", _c("button"), 56)
	back.custom_minimum_size = Vector2(110, 96)
	back.pressed.connect(close)
	head.add_child(back)
	var title := _label(_t("Descargar mapas"), 54, _c("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)

	# Buscador
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	col.add_child(srow)
	_edit = LineEdit.new()
	_edit.text = _query
	_edit.placeholder_text = _t("Título, artista o creador")
	_edit.clear_button_enabled = true
	_edit.custom_minimum_size = Vector2(0, 100)
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.add_theme_font_size_override("font_size", 36)
	_edit.add_theme_color_override("font_color", _c("text"))
	_edit.add_theme_color_override("font_placeholder_color", _c("muted"))
	_edit.add_theme_color_override("caret_color", _c("accent"))
	for st in ["normal", "focus"]:
		_edit.add_theme_stylebox_override(st, _style(_c("panel"), 24, 24))
	_edit.text_submitted.connect(func(_text: String) -> void: _search(true))
	srow.add_child(_edit)
	var go := _btn(_t("Buscar"), _c("accent"))
	go.custom_minimum_size = Vector2(230, 100)
	go.pressed.connect(func() -> void: _search(true))
	srow.add_child(go)

	# Modo
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	col.add_child(mrow)
	for m in [[MODE_MANIA, "osu!mania"], [MODE_STD, "osu!standard"], [MODE_ALL, "Todos"]]:
		var mb := _btn(_t(m[1]), _c("button"), 30)
		mb.custom_minimum_size = Vector2(0, 84)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.pressed.connect(_set_mode.bind(int(m[0])))
		mrow.add_child(mb)
		_mode_btns[int(m[0])] = mb

	# Filtros de estado + opción de video
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	col.add_child(flow)
	for st in STATUS_LIST:
		var cb := _btn(String(st[1]), _c("button"), 28)
		cb.custom_minimum_size = Vector2(0, 72)
		cb.pressed.connect(_toggle_status.bind(int(st[0])))
		flow.add_child(cb)
		_status_btns[int(st[0])] = cb
	_video_btn = _btn("", _c("button"), 28)
	_video_btn.custom_minimum_size = Vector2(0, 72)
	_video_btn.pressed.connect(_toggle_video)
	flow.add_child(_video_btn)
	_refresh_toggles()

	_status = _label("", 28, _c("muted"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	# Resultados
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE   # el arrastre lo maneja _input (ver arriba)
	col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 18)
	_scroll.add_child(_list)

	_append_cards(_sets)


func _set_toggle_style(b: Button, color: Color) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var box := _style(color, 24, 12)
		box.content_margin_left = 26
		box.content_margin_right = 26
		b.add_theme_stylebox_override(st, box)


## Pinta modo, estados y video según lo que esté activado.
func _refresh_toggles() -> void:
	for m in _mode_btns:
		_set_toggle_style(_mode_btns[m], _c("accent") if m == _mode else _c("button"))
	for code in _status_btns:
		_set_toggle_style(_status_btns[code], _c("accent") if _statuses.has(code) else _c("button"))
	if _video_btn != null:
		_video_btn.text = _t("Sin video: SÍ") if _no_video else _t("Sin video: NO")
		_set_toggle_style(_video_btn, _c("violet") if _no_video else _c("button"))


## Añade tarjetas al final de la lista (y recoloca el botón "Cargar más").
func _append_cards(sets: Array) -> void:
	if _more_btn != null and is_instance_valid(_more_btn):
		_list.remove_child(_more_btn)
		_more_btn.queue_free()
		_more_btn = null
	for s in sets:
		_add_card(s)
	if not _sets.is_empty() and not _end:
		_more_btn = _btn(_t("Cargar más"), _c("button"))
		_more_btn.custom_minimum_size = Vector2(0, 96)
		_more_btn.pressed.connect(_load_more)
		_list.add_child(_more_btn)


func _add_card(s: Dictionary) -> void:
	var sid: int = s.id
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(_c("card"), 28, 14))
	_list.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	card.add_child(row)

	# Portada (se rellena cuando llega; mientras, un fondo liso)
	var thumb_bg := PanelContainer.new()
	thumb_bg.add_theme_stylebox_override("panel", _style(_c("field"), 0, 0))
	thumb_bg.custom_minimum_size = Vector2(170, 170)
	thumb_bg.clip_contents = true
	row.add_child(thumb_bg)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb_bg.add_child(tr)
	_thumbs[sid] = tr
	if _covers.has(sid):
		tr.texture = _covers[sid]
	else:
		_dl.fetch_cover(sid)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	info.add_child(_label(s.title, 36, _c("ink"), true))
	info.add_child(_label("%s · %s" % [s.artist, _t("por %s") % s.creator], 26, _c("ink").lerp(_c("card"), 0.35), true))
	info.add_child(_label(_diff_summary(s.diffs), 24, _c("ink").lerp(_c("card"), 0.35), true))

	var b := _btn("", _c("accent"))
	b.custom_minimum_size = Vector2(230, 92)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_on_card_pressed.bind(sid))
	row.add_child(b)
	_card_btns[sid] = b
	_apply_state(sid)


func _on_cover(sid: int, tex: Texture2D) -> void:
	_covers[sid] = tex
	var tr: TextureRect = _thumbs.get(sid)
	if tr != null and is_instance_valid(tr):
		tr.texture = tex


## "4K x3 · 7K x1 · STD x2 · ★1.8-5.4"
static func _diff_summary(diffs: Array) -> String:
	if diffs.is_empty():
		return ""
	var counts := {}
	var lo := 999.0
	var hi := 0.0
	for d in diffs:
		var tag: String = ("%dK" % int(d["keys"])) if int(d.mode) == 3 else "STD"
		counts[tag] = int(counts.get(tag, 0)) + 1
		var st: float = d.stars
		if st > 0.0:
			lo = minf(lo, st)
			hi = maxf(hi, st)
	var parts: Array = []
	for tag in counts:
		parts.append("%s x%d" % [tag, counts[tag]])
	if hi > 0.0:
		parts.append("★%.1f-%.1f" % [lo, hi])
	return " · ".join(parts)


func _apply_state(sid: int) -> void:
	var b: Button = _card_btns.get(sid)
	if b == null or not is_instance_valid(b):
		return
	var st: String = _states.get(sid, "")
	if st == "" and Downloader.is_installed(sid):
		st = "done"
	b.disabled = true
	match st:
		"done": b.text = _t("Instalada")
		"queued": b.text = _t("En cola")
		"loading": b.text = "..."
		"importing": b.text = _t("Importando...")
		"failed": b.text = _t("No compatible")
		_:
			b.disabled = false
			b.text = _t("Reintentar") if st == "error" else _t("Descargar")


func _set_status(text: String, is_error: bool) -> void:
	if _status == null or not is_instance_valid(_status):
		return
	_status.text = text
	_status.add_theme_color_override("font_color", _c("danger") if is_error else _c("muted"))


# ---------------------------------------------------------------------------
# Acciones
# ---------------------------------------------------------------------------

func _toggle_status(code: int) -> void:
	if _statuses.has(code):
		_statuses.erase(code)
	else:
		_statuses.append(code)
	_refresh_toggles()
	_search(true)


func _toggle_video() -> void:
	_no_video = not _no_video
	_refresh_toggles()


func _set_mode(m: int) -> void:
	if m == _mode:
		return
	_mode = m
	_refresh_toggles()
	_search(true)


func _search(reset: bool) -> void:
	if reset:
		_query = _edit.text.strip_edges() if _edit != null else _query
		_page = 0
		_sets.clear()
		_end = false
		for c in _list.get_children():
			c.queue_free()
		_more_btn = null
		_card_btns.clear()
		_thumbs.clear()
		_dl.clear_cover_queue()
		if _edit != null:
			_edit.release_focus()
	_loading = true
	_set_status(_t("Buscando..."), false)
	_dl.search(_query, _mode, _page, _statuses)


func _load_more() -> void:
	if _drag_moved:
		return
	if not _loading and not _end:
		_search(false)


func _on_search(sets: Array, error: String) -> void:
	_loading = false
	if not error.is_empty():
		_set_status(_t(error), true)
		return
	var fresh: Array = []
	for s in sets:
		var known := false
		for k in _sets:
			if k.id == s.id:
				known = true
				break
		if not known:
			fresh.append(s)
	_sets.append_array(fresh)
	_page += 1
	if _dl.last_raw_count == 0:
		_end = true
	_set_status(_t("Sin resultados") if _sets.is_empty() else "", false)
	_append_cards(fresh)


func _on_card_pressed(sid: int) -> void:
	if _drag_moved:
		return   # fue un arrastre para desplazar, no un toque
	_states[sid] = "queued"
	_apply_state(sid)
	_set_status("", false)
	_dl.download(sid, _no_video)


func _on_progress(sid: int, got: int, total: int) -> void:
	_states[sid] = "loading"
	var b: Button = _card_btns.get(sid)
	if b == null or not is_instance_valid(b):
		return
	b.disabled = true
	if total > 0:
		b.text = "%d%%" % int(100.0 * float(got) / float(total))
	else:
		b.text = "%.1f MB" % (float(got) / 1048576.0)


func _on_download(sid: int, path: String, error: String) -> void:
	if not error.is_empty():
		_states[sid] = "error"
		_apply_state(sid)
		_set_status(_t(error), true)
		return
	_states[sid] = "importing"
	_apply_state(sid)
	osz_ready.emit(path, sid)
