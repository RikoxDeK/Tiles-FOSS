extends Node
## Cliente de mirrors de beatmaps de osu!: busca en Mino (catboy.best) y descarga .osz,
## con otros mirrors de respaldo. Solo hace red: no toca la UI ni la biblioteca.
##
## Uso:
##   var dl := preload("res://scripts/beatmap_downloader.gd").new()
##   add_child(dl)
##   dl.search_finished.connect(...)   # (sets: Array, error: String)
##   dl.search("camellia", 3, 0)       # texto, modo (3 mania, 0 standard, -1 todos), página
##   dl.download(set_id)               # -> download_progress / download_finished
##
## Formato de un set devuelto por search():
##   {"id": int, "title", "artist", "creator": String,
##    "diffs": [{"mode": 0|3, "keys": int, "stars": float, "name": String}]}

signal search_finished(sets: Array, error: String)
signal download_progress(set_id: int, got: int, total: int)
signal download_finished(set_id: int, path: String, error: String)
signal cover_loaded(set_id: int, tex: Texture2D)

## Opcional: Godot ya manda su propio User-Agent si no pones ninguno. Poner uno propio solo ayuda
## a los mantenedores del mirror a distinguir tu app de tráfico abusivo.
const USER_AGENT := "TilesFOSS/0.1"
const SEARCH_URL := "https://catboy.best/api/v2/search"
## Portada cuadrada (300x300) del CDN oficial de osu!.
const COVER_URL := "https://assets.ppy.sh/beatmaps/%d/covers/list@2x.jpg"
const COVER_WORKERS := 3
const TMP_DIR := "user://tmp"
const SEARCH_TIMEOUT := 20.0
const DOWNLOAD_TIMEOUT := 600.0
## Un .osz real pesa mucho más; menos que esto es una página de error.
const MIN_OSZ_BYTES := 2048

## Límites de tasa: si un mirror responde 429 (demasiadas peticiones) se le deja descansar y no se le
## vuelve a pedir nada hasta que pase el tiempo de Retry-After (o COOLDOWN_DEFAULT). Insistir hace que
## el mirror banee a los usuarios de la app. Las descargas se controlan por host y las búsquedas aparte.
const COOLDOWN_DEFAULT := 30.0
const COOLDOWN_MIN := 5.0
const COOLDOWN_MAX := 300.0
## Si una descarga buena avisa de que no quedan peticiones (X-Ratelimit-Remaining: 0), se espera esto.
const COOLDOWN_NO_REMAINING := 10.0
const SEARCH_KEY := "catboy.best/search"
const MSG_LIMITED := "El mirror está limitando las peticiones. Espera un momento y reintenta"

## Cuántos resultados crudos devolvió la última búsqueda (antes de filtrar por modo).
var last_raw_count := 0

var _search_http: HTTPRequest
var _dl_http: HTTPRequest
var _pending_mode := -1
var _queue: Array = []        # [{"id": int, "nv": bool}]
var _cur_nv := true
var _cover_http: Array = []
var _cover_job := {}          # HTTPRequest -> set_id
var _cover_queue: Array = []
var _cover_cache := {}
var _cur_id := 0
var _cur_urls: Array = []
var _cur_i := 0
var _cur_limited := false     # algún mirror respondió 429 durante la descarga actual
var _cooldown := {}           # clave (host o host/search) -> Time.get_ticks_msec() hasta el que descansa


func _ready() -> void:
	_search_http = HTTPRequest.new()
	_search_http.timeout = SEARCH_TIMEOUT
	_search_http.request_completed.connect(_on_search_done)
	add_child(_search_http)
	_dl_http = HTTPRequest.new()
	_dl_http.timeout = DOWNLOAD_TIMEOUT
	_dl_http.use_threads = true
	_dl_http.request_completed.connect(_on_download_done)
	add_child(_dl_http)
	for i in COVER_WORKERS:
		var h := HTTPRequest.new()
		h.timeout = SEARCH_TIMEOUT
		h.request_completed.connect(_on_cover_done.bind(h))
		add_child(h)
		_cover_http.append(h)
	set_process(false)


## Id de carpeta en user://songs para un set descargado. Son 10 dígitos hex (como los ids
## por md5 de los .osz importados a mano) para que el respaldo y la restauración lo entiendan,
## y siempre el mismo por set: así no se duplica ni se vuelve a descargar.
static func local_id(set_id: int) -> String:
	return "%010x" % set_id


static func is_installed(set_id: int) -> bool:
	return DirAccess.dir_exists_absolute("user://songs".path_join(local_id(set_id)))


# ---------------------------------------------------------------------------
# Búsqueda
# ---------------------------------------------------------------------------

## mode: 3 = mania, 0 = standard, -1 = todos. page empieza en 0.
## statuses: códigos de estado de osu! (1 ranked, 2 approved, 3 qualified, 4 loved, 0 pending,
## -1 WIP, -2 graveyard). Vacío = sin filtrar por estado.
func search(query: String, mode: int, page: int, statuses: Array = []) -> void:
	_search_http.cancel_request()
	if _is_cooling(SEARCH_KEY):
		last_raw_count = 0
		search_finished.emit([], MSG_LIMITED)
		return
	var url := "%s?q=%s&mode=%d&p=%d" % [SEARCH_URL, query.uri_encode(), mode, page]
	for st in statuses:
		url += "&status=%d" % int(st)
	var headers := PackedStringArray(["User-Agent: " + USER_AGENT, "Accept: application/json"])
	if _search_http.request(url, headers) != OK:
		search_finished.emit([], "No se pudo iniciar la búsqueda")
		return
	_pending_mode = mode


func _on_search_done(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	last_raw_count = 0
	if result != HTTPRequest.RESULT_SUCCESS:
		search_finished.emit([], "Sin conexión con el mirror")
		return
	if code == 429:
		_cool_down(SEARCH_KEY, headers)
		search_finished.emit([], MSG_LIMITED)
		return
	if code != 200:
		search_finished.emit([], "El mirror respondió con error (%d)" % code)
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	var raw: Array = []
	if json is Array:
		raw = json
	elif json is Dictionary:
		var inner: Variant = json.get("beatmapsets", json.get("data", []))
		if inner is Array:
			raw = inner
	last_raw_count = raw.size()
	var sets: Array = []
	for d in raw:
		if d is Dictionary:
			var s := _parse_set(d, _pending_mode)
			if not s.is_empty():
				sets.append(s)
	search_finished.emit(sets, "")


## Convierte un set del mirror al formato interno. Tolera los nombres de campo de la API de
## osu! (id, beatmaps, mode_int, difficulty_rating) y variantes habituales de los mirrors.
## Devuelve {} si el set no tiene ninguna dificultad compatible (mania/standard).
static func _parse_set(d: Dictionary, want_mode: int) -> Dictionary:
	var id: int = int(d.get("id", d.get("beatmapset_id", d.get("SetID", 0))))
	if id <= 0:
		return {}
	var maps: Variant = d.get("beatmaps", d.get("ChildrenBeatmaps", []))
	var diffs: Array = []
	if maps is Array:
		for b in maps:
			if not (b is Dictionary):
				continue
			var m := _mode_of(b)
			if m != 0 and m != 3:
				continue
			if want_mode >= 0 and m != want_mode:
				continue
			diffs.append({
				"mode": m,
				"keys": int(round(float(b.get("cs", b.get("CS", 4))))),
				"stars": float(b.get("difficulty_rating", b.get("DifficultyRating", 0.0))),
				"name": str(b.get("version", b.get("DiffName", ""))),
			})
		if diffs.is_empty():
			return {}   # el set solo trae taiko/catch (o el otro modo)
	return {
		"id": id,
		"title": str(d.get("title", d.get("Title", "?"))),
		"artist": str(d.get("artist", d.get("Artist", "?"))),
		"creator": str(d.get("creator", d.get("Creator", "?"))),
		"diffs": diffs,
	}


static func _mode_of(b: Dictionary) -> int:
	if b.has("mode_int"):
		return int(b.mode_int)
	var m: Variant = b.get("mode", b.get("Mode", -1))
	if m is String:
		var names := {"osu": 0, "taiko": 1, "fruits": 2, "catch": 2, "mania": 3}
		return int(names.get(String(m).to_lower(), -1))
	return int(m)


# ---------------------------------------------------------------------------
# Descarga (una a la vez, en cola)
# ---------------------------------------------------------------------------

## no_video: pide la versión sin video a Mino (pesa mucho menos; el juego no usa el video).
func download(set_id: int, no_video := true) -> void:
	if set_id <= 0 or set_id == _cur_id:
		return
	for q in _queue:
		if q.id == set_id:
			return
	_queue.append({"id": set_id, "nv": no_video})
	_next()


func _next() -> void:
	if _cur_id != 0 or _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	_cur_id = int(job.id)
	_cur_nv = bool(job.nv)
	_cur_urls = _urls_for(_cur_id, _cur_nv)
	_cur_i = 0
	_cur_limited = false
	_try_current()


## Mino primero (la "n" final = sin video; si fallara se prueba el enlace normal) y, si falla, otros mirrors.
## Los mirrors de respaldo se piden sin opciones: pueden traer video, el importador lo ignora.
func _urls_for(id: int, no_video: bool) -> Array:
	var urls: Array = []
	if no_video:
		urls.append("https://catboy.best/d/%dn" % id)
	urls.append("https://catboy.best/d/%d" % id)
	urls.append("https://api.nerinyan.moe/d/%d" % id)
	urls.append("https://osu.direct/api/d/%d" % id)
	return urls


func _try_current() -> void:
	while _cur_i < _cur_urls.size():
		if _is_cooling(_host_of(_cur_urls[_cur_i])):
			_cur_limited = true   # ese mirror pidió calma: se salta sin tocarlo
			_cur_i += 1
			continue
		DirAccess.make_dir_recursive_absolute(TMP_DIR)
		_dl_http.download_file = TMP_DIR.path_join("%d.osz" % _cur_id)
		var headers := PackedStringArray(["User-Agent: " + USER_AGENT])
		if _dl_http.request(_cur_urls[_cur_i], headers) == OK:
			set_process(true)
			download_progress.emit(_cur_id, 0, -1)
			return
		_cur_i += 1
	_finish(MSG_LIMITED if _cur_limited else "No se pudo descargar desde ningún mirror")


func _on_download_done(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	var host := _host_of(_cur_urls[_cur_i]) if _cur_i < _cur_urls.size() else ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and _looks_like_osz(_dl_http.download_file):
		if _header(headers, "x-ratelimit-remaining") == "0":
			_cool_down(host, headers, COOLDOWN_NO_REMAINING)
		_finish("")
		return
	if code == 429:
		_cool_down(host, headers)   # el siguiente enlace de este mismo host también se salta
		_cur_limited = true
	DirAccess.remove_absolute(_dl_http.download_file)
	_cur_i += 1
	_try_current.call_deferred()


## "https://catboy.best/d/123" -> "catboy.best"
static func _host_of(url: String) -> String:
	return url.get_slice("/", 2)


## Valor de una cabecera HTTP (sin distinguir mayúsculas) o "" si no viene.
static func _header(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ":"
	for h in headers:
		if h.to_lower().begins_with(prefix):
			return h.substr(prefix.length()).strip_edges()
	return ""


func _is_cooling(key: String) -> bool:
	return int(_cooldown.get(key, 0)) > Time.get_ticks_msec()


## Deja descansar a `key` el tiempo de Retry-After (en segundos; si no viene o es una fecha, `fallback`).
func _cool_down(key: String, headers: PackedStringArray, fallback := COOLDOWN_DEFAULT) -> void:
	var secs := fallback
	var ra := _header(headers, "retry-after")
	if ra.is_valid_float():
		secs = ra.to_float()
	secs = clampf(secs, COOLDOWN_MIN, COOLDOWN_MAX)
	_cooldown[key] = Time.get_ticks_msec() + int(secs * 1000.0)


## Un .osz es un zip: empieza por "PK\x03\x04". Algunos mirrors devuelven una página HTML con código 200.
static func _looks_like_osz(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < MIN_OSZ_BYTES:
		return false
	var head := f.get_buffer(4)
	return head.size() == 4 and head[0] == 0x50 and head[1] == 0x4B and head[2] == 0x03 and head[3] == 0x04


func _finish(error: String) -> void:
	var id := _cur_id
	var path: String = _dl_http.download_file
	_cur_id = 0
	if not error.is_empty():
		DirAccess.remove_absolute(path)
		path = ""
	download_finished.emit(id, path, error)
	_next()
	if _cur_id == 0:
		set_process(false)


func _process(_delta: float) -> void:
	if _cur_id != 0:
		download_progress.emit(_cur_id, _dl_http.get_downloaded_bytes(), _dl_http.get_body_size())


# ---------------------------------------------------------------------------
# Portadas (hasta COVER_WORKERS a la vez, con caché en memoria)
# ---------------------------------------------------------------------------

func fetch_cover(set_id: int) -> void:
	if _cover_cache.has(set_id):
		cover_loaded.emit.call_deferred(set_id, _cover_cache[set_id])
		return
	if _cover_queue.has(set_id) or _cover_job.values().has(set_id):
		return
	_cover_queue.append(set_id)
	_pump_covers()


## Descarta las portadas pendientes (al cambiar de búsqueda); las que ya van en camino terminan.
func clear_cover_queue() -> void:
	_cover_queue.clear()


func _pump_covers() -> void:
	for h in _cover_http:
		if _cover_queue.is_empty():
			return
		if _cover_job.has(h):
			continue
		var id := int(_cover_queue.pop_front())
		_cover_job[h] = id
		if h.request(COVER_URL % id, PackedStringArray(["User-Agent: " + USER_AGENT])) != OK:
			_cover_job.erase(h)


func _on_cover_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, h: HTTPRequest) -> void:
	var id := int(_cover_job.get(h, 0))
	_cover_job.erase(h)
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and id != 0:
		var tex := _decode_image(body)
		if tex != null:
			_cover_cache[id] = tex
			cover_loaded.emit(id, tex)
	_pump_covers()


static func _decode_image(bytes: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		if img.load_png_from_buffer(bytes) != OK:
			if img.load_webp_from_buffer(bytes) != OK:
				return null
	return ImageTexture.create_from_image(img)
