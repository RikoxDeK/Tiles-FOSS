extends RefCounted
## Importador de beatmaps de osu! (.osz / .osu) al formato interno de Tiles FOSS.
##
## Modos soportados:
##   - osu!mania (Mode 3): cualquier número de teclas. 4K se mapea 1:1; el resto
##     se comprime a 4 carriles.
##   - osu!standard (Mode 0): el carril sale de la posición X del círculo y los
##     sliders se convierten en notas sostenidas. Es una conversión aproximada.
##   - taiko y catch no están soportados.
##
## Formato interno de una nota:
##   {"time": seg, "lane": 0..3, "type": "tap"}
##   {"time": seg, "lane": 0..3, "type": "hold", "duration": seg}

const LANES := 4
const SONGS_DIR := "user://songs"
const AUDIO_EXTENSIONS := ["mp3", "ogg"]
const IMAGE_EXTENSIONS := ["jpg", "jpeg", "png", "webp", "bmp"]

## Segundos mínimos entre dos notas del mismo carril (evita jacks imposibles).
const MIN_LANE_GAP := 0.12
## Los holds más cortos que esto se convierten en tap.
const MIN_HOLD := 0.15
## Notas dentro de esta ventana (desde la primera del grupo) forman un acorde.
const CHORD_WINDOW := 0.06
## Segundos mínimos entre un grupo de notas (acorde o nota suelta) y el siguiente.
## 0.16 s = unas 6 pulsaciones por segundo, razonable con dos pulgares en vertical.
const MIN_EVENT_GAP := 0.16
## Dedos que se asumen disponibles a la vez (README: "multitáctil para dos dedos").
## Un hold ocupa un dedo mientras dura.
const DEFAULT_MAX_FINGERS := 2

## Reglas de comodidad (carriles 0..3 = 1..4 en pantalla):
##  - Dobles: no se permiten en dos carriles pegados de un costado (1+2 ni 3+4).
##    Sí valen el centro (2+3), con un espacio (1+3, 2+4) y los extremos (1+4).
##  - Nota sostenida + nota normal a la vez: deben estar en lados opuestos.
##    Sostenida en 1-2 -> normales solo en 3-4; sostenida en 3-4 -> normales solo en 1-2.
const HOLD_SIDE_MAX_LANE := 1

## Velocidad base del juego (px/s) y separación visual objetivo entre filas de notas.
const BASE_SPEED := 760.0
const TARGET_ROW_PX := 200.0
const AUTO_SPEED_MIN := 1.0
const AUTO_SPEED_MAX := 2.0


# ---------------------------------------------------------------------------
# Parseo de un .osu
# ---------------------------------------------------------------------------

## Parsea el texto de un .osu. Con header_only=true se detiene antes de
## [HitObjects] (suficiente para listar la biblioteca).
static func parse_osu(text: String, header_only := false) -> Dictionary:
	var r := {
		"ok": false, "error": "", "mode": 0, "keys": 4,
		"title": "", "artist": "", "creator": "", "version": "",
		"audio": "", "background": "", "slider_multiplier": 1.4,
		"timing": [], "objects": []
	}
	var section := ""
	var first := true
	for raw in text.split("\n"):
		var line: String = raw.strip_edges()
		if first:
			line = line.trim_prefix(char(0xFEFF))
			first = false
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			if header_only and section == "HitObjects":
				break
			continue
		if section == "General" or section == "Metadata" or section == "Difficulty":
			var idx := line.find(":")
			if idx < 0:
				continue
			var key := line.substr(0, idx).strip_edges()
			var val := line.substr(idx + 1).strip_edges()
			if key == "AudioFilename": r.audio = val
			elif key == "Mode": r.mode = int(val)
			elif key == "Title": r.title = val
			elif key == "Artist": r.artist = val
			elif key == "Creator": r.creator = val
			elif key == "Version": r.version = val
			elif key == "CircleSize": r.keys = int(round(float(val)))
			elif key == "SliderMultiplier": r.slider_multiplier = float(val)
		elif section == "Events":
			# Línea de imagen de fondo:  0,0,"archivo.jpg",0,0
			var ev := line.split(",")
			if ev.size() >= 3 and ev[0].strip_edges() == "0" and ev[1].strip_edges() == "0" and r.background.is_empty():
				r.background = ev[2].strip_edges().trim_prefix("\"").trim_suffix("\"")
		elif section == "TimingPoints":
			if header_only:
				continue
			var p := line.split(",")
			if p.size() >= 2:
				r.timing.append({"time": float(p[0]), "beat": float(p[1])})
		elif section == "HitObjects":
			_parse_object(line, r)

	if r.mode != 0 and r.mode != 3:
		r.error = "Modo no soportado (solo osu!mania y osu!standard)"
	elif r.audio.is_empty():
		r.error = "El mapa no declara archivo de audio"
	elif not header_only and r.objects.is_empty():
		r.error = "El mapa no tiene notas"
	else:
		r.ok = true
	return r


static func _parse_object(line: String, r: Dictionary) -> void:
	var p := line.split(",")
	if p.size() < 5:
		return
	var x := float(p[0])
	var t := float(p[2]) / 1000.0
	var kind := int(p[3])
	var lane := 0
	if r.mode == 3:
		var keys: int = maxi(r.keys, 1)
		lane = clampi(int(floor(x * keys / 512.0)), 0, keys - 1)
		lane = int(floor(lane * float(LANES) / keys))  # 4K queda igual
		if kind & 128:
			var end := t
			if p.size() > 5:
				end = float(p[5].split(":")[0]) / 1000.0
			r.objects.append({"time": t, "lane": lane, "end": maxf(end, t)})
		elif kind & 1:
			r.objects.append({"time": t, "lane": lane, "end": t})
	elif r.mode == 0:
		lane = clampi(int(x / 512.0 * LANES), 0, LANES - 1)
		if kind & 2 and p.size() >= 8:
			var slides := maxi(int(p[6]), 1)
			var dur := _slider_duration(r, t * 1000.0, float(p[7]), slides)
			r.objects.append({"time": t, "lane": lane, "end": t + dur})
		elif kind & 1:
			r.objects.append({"time": t, "lane": lane, "end": t})


static func _slider_duration(r: Dictionary, t_ms: float, length: float, slides: int) -> float:
	var beat := -1.0
	var first_beat := -1.0
	var mult := 1.0
	for tp in r.timing:
		if tp.beat > 0.0 and first_beat < 0.0:
			first_beat = tp.beat
		if tp.time > t_ms:
			break
		if tp.beat > 0.0:
			beat = tp.beat
			mult = 1.0
		elif tp.beat < 0.0:
			mult = clampf(-100.0 / tp.beat, 0.1, 10.0)
	if beat < 0.0:
		beat = first_beat if first_beat > 0.0 else 500.0
	var ms: float = length / (r.slider_multiplier * 100.0 * mult) * beat * slides
	return ms / 1000.0


# ---------------------------------------------------------------------------
# Conversión a chart interno
# ---------------------------------------------------------------------------

## Convierte los objetos parseados en notas jugables, ordenadas por tiempo.
## Descarta lo que no cabe en 4 carriles / max_fingers dedos.
static func build_chart(parsed: Dictionary, max_fingers := DEFAULT_MAX_FINGERS, event_gap := MIN_EVENT_GAP, lane_gap := MIN_LANE_GAP) -> Array:
	var objs: Array = parsed.objects.duplicate(true)
	objs.sort_custom(func(a, b): return a.time < b.time)

	var busy_until := [-100.0, -100.0, -100.0, -100.0]
	var live: Array = []
	var event_time := -100.0   # inicio del grupo (acorde) actual
	var chart: Array = []
	for o in objs:
		if o.end - o.time < MIN_HOLD:
			o.end = o.time
		var lane: int = o.lane
		if o.time - busy_until[lane] < lane_gap:
			continue
		var in_chord: bool = o.time - event_time <= CHORD_WINDOW
		if not in_chord and o.time - event_time < event_gap:
			continue
		# Dedos ocupados: holds en curso + notas del mismo grupo.
		var group_start: float = event_time if in_chord else o.time
		live = live.filter(func(n): return n.end > group_start or n.time >= group_start)
		if live.size() >= max_fingers:
			continue
		# Reglas de comodidad: reubica la nota a un carril válido; si es sostenida
		# y no hay sitio, la baja a nota normal; si aun así no cabe, se descarta.
		var placed := _find_lane(o, live, busy_until, lane_gap)
		if placed < 0 and o.end > o.time:
			o.end = o.time
			placed = _find_lane(o, live, busy_until, lane_gap)
		if placed < 0:
			continue
		lane = placed
		o.lane = placed
		if not in_chord:
			event_time = o.time
		live.append(o)
		busy_until[lane] = o.end
		var note := {"time": o.time, "lane": lane, "type": "tap"}
		if o.end > o.time:
			note.type = "hold"
			note.duration = o.end - o.time
		chart.append(note)
	return chart


## ¿Pueden pulsarse a la vez estos dos carriles? (ver reglas arriba)
static func _pair_ok(lane_a: int, hold_a: bool, lane_b: int, hold_b: bool) -> bool:
	if lane_a == lane_b:
		return false
	var lo := mini(lane_a, lane_b)
	var hi := maxi(lane_a, lane_b)
	if (lo == 0 and hi == 1) or (lo == 2 and hi == 3):
		return false
	if hold_a != hold_b:
		# Sostenida y normal a la vez: cada una en un lado distinto de la pantalla
		# (sostenida en 1-2 -> normal en 3-4, sostenida en 3-4 -> normal en 1-2).
		var hold_lane := lane_a if hold_a else lane_b
		var tap_lane := lane_b if hold_a else lane_a
		if (hold_lane <= HOLD_SIDE_MAX_LANE) == (tap_lane <= HOLD_SIDE_MAX_LANE):
			return false
	return true


## Carril válido para la nota o (el suyo, o el más cercano que cumpla las
## reglas contra las notas que ya ocupan dedos). -1 si no hay ninguno.
static func _find_lane(o: Dictionary, live: Array, busy_until: Array, lane_gap := MIN_LANE_GAP) -> int:
	var is_hold: bool = o.end > o.time
	var order: Array = [o.lane]
	for d in range(1, LANES):
		if o.lane - d >= 0:
			order.append(o.lane - d)
		if o.lane + d < LANES:
			order.append(o.lane + d)
	for candidate in order:
		if o.time - busy_until[candidate] < lane_gap:
			continue
		var ok := true
		for p in live:
			if not _pair_ok(p.lane, p.end > p.time, candidate, is_hold):
				ok = false
				break
		if ok:
			return candidate
	return -1


# ---------------------------------------------------------------------------
# Importar .osz y biblioteca en disco
# ---------------------------------------------------------------------------

static func safe_name(file_name: String) -> String:
	var out := file_name.get_file()
	for c in ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]:
		out = out.replace(c, "_")
	return out.strip_edges()


## Extrae un .osz a user://songs/<id>/ (solo los .osu compatibles y su audio).
## Devuelve {"ok", "error", "title", "count"}.
static func import_osz(path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(path) != OK:
		return {"ok": false, "error": "No se pudo abrir el archivo .osz"}
	var maps: Array = []
	var audio_names := {}
	var bg_names := {}
	var title := ""
	for f in zr.get_files():
		if not f.to_lower().ends_with(".osu"):
			continue
		var text := zr.read_file(f).get_string_from_utf8()
		var parsed := parse_osu(text, true)
		if not parsed.ok:
			continue
		maps.append({"name": safe_name(f), "text": text})
		audio_names[parsed.audio] = true
		if not parsed.background.is_empty() and parsed.background.get_extension().to_lower() in IMAGE_EXTENSIONS:
			bg_names[parsed.background] = true
		if title.is_empty():
			title = parsed.title
	if maps.is_empty():
		zr.close()
		return {"ok": false, "error": "No hay mapas compatibles (osu!mania u osu!standard)"}

	var id := FileAccess.get_md5(path).substr(0, 10)
	if id.is_empty():
		id = str(hash(path))
	var dir := SONGS_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)

	for m in maps:
		var file := FileAccess.open(dir.path_join(m.name), FileAccess.WRITE)
		if file == null:
			zr.close()
			return {"ok": false, "error": "No se pudo escribir en el almacenamiento"}
		file.store_string(m.text)
		file.close()

	for wanted in audio_names.keys():
		for f in zr.get_files():
			if f.get_file().to_lower() == String(wanted).get_file().to_lower():
				var out := FileAccess.open(dir.path_join(safe_name(wanted)), FileAccess.WRITE)
				if out != null:
					out.store_buffer(zr.read_file(f))
					out.close()
				break
	for wanted in bg_names.keys():
		for f in zr.get_files():
			if f.get_file().to_lower() == String(wanted).get_file().to_lower():
				var bout := FileAccess.open(dir.path_join(safe_name(wanted)), FileAccess.WRITE)
				if bout != null:
					bout.store_buffer(zr.read_file(f))
					bout.close()
				break
	zr.close()
	return {"ok": true, "error": "", "title": title, "count": maps.size()}


## Lista los mapas importados leyendo solo la cabecera de cada .osu.
static func scan_library() -> Array:
	var entries: Array = []
	var root := DirAccess.open(SONGS_DIR)
	if root == null:
		return entries
	for sub in root.get_directories():
		var dir := SONGS_DIR.path_join(sub)
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			if not f.to_lower().ends_with(".osu"):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			var parsed := parse_osu(text, true)
			if not parsed.ok:
				continue
			entries.append({
				"demo": false,
				"set_id": sub,
				"size": text.length(),
				"osu_path": dir.path_join(f),
				"audio_path": dir.path_join(safe_name(parsed.audio)),
				"bg_path": dir.path_join(safe_name(parsed.background)) if not parsed.background.is_empty() else "",
				"title": parsed.title, "artist": parsed.artist,
				"version": parsed.version, "creator": parsed.creator,
				"badge": ("%dK" % parsed.keys) if parsed.mode == 3 else "STD",
			})
	entries.sort_custom(func(a, b):
		if a.title != b.title:
			return a.title.naturalnocasecmp_to(b.title) < 0
		return a.version.naturalnocasecmp_to(b.version) < 0)
	return entries


## Carga una imagen (jpg/png/webp/bmp) como textura; la reduce a 1920 px como máximo.
## Devuelve null si no existe o no se puede leer.
static func load_image(path: String, max_side := 1920) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match path.get_extension().to_lower():
		"jpg", "jpeg": err = img.load_jpg_from_buffer(bytes)
		"png": err = img.load_png_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
		"bmp": err = img.load_bmp_from_buffer(bytes)
	if err != OK:  # extensión que no coincide con el contenido real
		err = img.load_jpg_from_buffer(bytes)
		if err != OK: err = img.load_png_from_buffer(bytes)
		if err != OK: return null
	var longest := maxi(img.get_width(), img.get_height())
	if longest > max_side:
		var k := float(max_side) / float(longest)
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


## Carga mp3/ogg desde disco. Devuelve null si no existe o el formato no sirve.
static func load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var ext := path.get_extension().to_lower()
	if not ext in AUDIO_EXTENSIONS:
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	if ext == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	return AudioStreamOggVorbis.load_from_buffer(bytes)


## Multiplicador de velocidad sugerido (1.0 = BASE_SPEED) para que las filas de
## notas no se amontonen: usa el 10% de separaciones más pequeñas entre grupos.
static func suggest_speed(chart: Array, event_gap := MIN_EVENT_GAP) -> float:
	var gaps: Array = []
	var last := -100.0
	for n in chart:
		if n.time - last > CHORD_WINDOW:
			if last > -50.0:
				gaps.append(n.time - last)
			last = n.time
	if gaps.size() < 5:
		return AUTO_SPEED_MIN
	gaps.sort()
	var p10: float = gaps[int(gaps.size() * 0.1)]
	var mult: float = TARGET_ROW_PX / (maxf(p10, event_gap) * BASE_SPEED)
	return snappedf(clampf(mult, AUTO_SPEED_MIN, AUTO_SPEED_MAX), 0.1)
