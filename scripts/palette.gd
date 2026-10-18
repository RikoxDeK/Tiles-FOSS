extends RefCounted
## Paleta de colores editable: cada "rol" es un color que se usa en muchas partes de la app.
## main.gd los lee con pcol("id"). Los valores de aquí son los de fábrica.

const ROLES := [
	{"id": "bg", "name": "Fondo", "def": Color(0.025, 0.05, 0.1)},
	{"id": "accent", "name": "Principal", "def": Color(0.02, 0.68, 0.88)},
	{"id": "panel", "name": "Paneles", "def": Color(0.08, 0.13, 0.22)},
	{"id": "button", "name": "Botones", "def": Color(0.17, 0.25, 0.37)},
	{"id": "card", "name": "Tarjetas", "def": Color(0.97, 0.98, 1.0)},
	{"id": "ink", "name": "Texto tarjeta", "def": Color(0.12, 0.22, 0.31)},
	{"id": "text", "name": "Texto", "def": Color(1.0, 1.0, 1.0)},
	{"id": "muted", "name": "Texto suave", "def": Color(0.62, 0.75, 0.88)},
	{"id": "nav", "name": "Barra", "def": Color(0.05, 0.09, 0.17)},
	{"id": "nav_home", "name": "Inicio", "def": Color(0.22, 0.5, 0.95)},
	{"id": "nav_music", "name": "Música", "def": Color(0.95, 0.36, 0.58)},
	{"id": "nav_files", "name": "Archivos", "def": Color(0.97, 0.6, 0.2)},
	{"id": "nav_settings", "name": "Ajustes", "def": Color(0.2, 0.75, 0.45)},
	{"id": "violet", "name": "Infinito", "def": Color(0.5, 0.38, 0.92)},
	{"id": "fav", "name": "Favoritas", "def": Color(0.93, 0.27, 0.4)},
	{"id": "danger", "name": "Peligro", "def": Color(0.85, 0.22, 0.32)},
	{"id": "gold", "name": "Oro", "def": Color(1.0, 0.82, 0.3)},
	{"id": "field", "name": "Campo", "def": Color(0.74, 0.88, 0.98)},
	{"id": "tile", "name": "Teclas", "def": Color(0.01, 0.01, 0.015)},
	{"id": "hold", "name": "Largas", "def": Color(0.0, 0.95, 1.0)},
	{"id": "perfect", "name": "Perfect", "def": Color(1.0, 0.78, 0.12)},
	{"id": "great", "name": "Great", "def": Color(0.05, 0.82, 0.95)},
	{"id": "good", "name": "Good", "def": Color(0.3, 0.85, 0.45)},
	{"id": "miss", "name": "Fallo", "def": Color(1.0, 0.25, 0.3)},
]

## Paletas listas: solo cambian los roles que indican; el resto queda de fábrica.
const PRESETS := [
	{"name": "Original", "over": {}},
	{"name": "Atardecer", "over": {"bg": Color(0.1, 0.04, 0.07), "accent": Color(1.0, 0.55, 0.25), "panel": Color(0.22, 0.1, 0.14), "button": Color(0.38, 0.2, 0.26), "card": Color(1.0, 0.97, 0.94), "ink": Color(0.3, 0.14, 0.14), "muted": Color(0.95, 0.74, 0.7), "nav": Color(0.16, 0.07, 0.1), "nav_home": Color(0.98, 0.45, 0.3), "nav_music": Color(0.95, 0.3, 0.55), "nav_files": Color(1.0, 0.7, 0.25), "nav_settings": Color(0.75, 0.4, 0.85), "violet": Color(0.8, 0.35, 0.6), "fav": Color(0.95, 0.3, 0.45), "danger": Color(0.8, 0.15, 0.25), "field": Color(0.99, 0.88, 0.8), "tile": Color(0.15, 0.05, 0.07), "hold": Color(1.0, 0.7, 0.3)}},
	{"name": "Bosque", "over": {"bg": Color(0.02, 0.07, 0.05), "accent": Color(0.2, 0.8, 0.5), "panel": Color(0.07, 0.18, 0.14), "button": Color(0.14, 0.3, 0.24), "card": Color(0.96, 1.0, 0.97), "ink": Color(0.1, 0.28, 0.2), "muted": Color(0.65, 0.88, 0.75), "nav": Color(0.04, 0.12, 0.09), "nav_home": Color(0.25, 0.75, 0.55), "nav_music": Color(0.9, 0.55, 0.35), "nav_files": Color(0.9, 0.75, 0.25), "nav_settings": Color(0.3, 0.6, 0.9), "violet": Color(0.3, 0.65, 0.8), "field": Color(0.8, 0.93, 0.82), "tile": Color(0.02, 0.05, 0.03), "hold": Color(0.5, 1.0, 0.7)}},
	{"name": "Violeta", "over": {"bg": Color(0.05, 0.03, 0.1), "accent": Color(0.65, 0.45, 1.0), "panel": Color(0.14, 0.1, 0.26), "button": Color(0.26, 0.2, 0.42), "card": Color(0.97, 0.96, 1.0), "ink": Color(0.2, 0.14, 0.34), "muted": Color(0.78, 0.72, 0.95), "nav": Color(0.09, 0.06, 0.17), "nav_home": Color(0.5, 0.45, 1.0), "nav_music": Color(1.0, 0.4, 0.7), "nav_files": Color(1.0, 0.65, 0.3), "nav_settings": Color(0.3, 0.8, 0.7), "violet": Color(0.9, 0.4, 0.9), "field": Color(0.86, 0.82, 0.98), "tile": Color(0.04, 0.02, 0.08), "hold": Color(0.8, 0.6, 1.0)}},
]

static func defaults() -> Dictionary:
	var d := {}
	for r in ROLES:
		d[r.id] = r.def
	return d

static func preset(i: int) -> Dictionary:
	var d := defaults()
	var over: Dictionary = PRESETS[i].over
	for k in over:
		d[k] = over[k]
	return d
