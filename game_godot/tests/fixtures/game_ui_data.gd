## Localized owned collection fixture copied from the app ARBs: enough owned paints to exercise scrolling.
extends RefCounted


static func collection(lang: String) -> Dictionary:
	var localized: Dictionary = {
		"ru": {
			"name": "Хэтчбек",
			"texts": {
				"start": "Начать заезд",
				"no_runs": "Начать заезд",
				"colour": "Цвет",
				"record": "Рекорд",
				"runs": "Заезды 3 из 3"
			},
			"paints": [
				{
					"paint": "red",
					"name": "красный",
					"hex": "#ED4621"
				},
				{
					"paint": "white",
					"name": "белый",
					"hex": "#FFFFFF"
				},
				{
					"paint": "silver",
					"name": "серебристый",
					"hex": "#CACACA"
				},
				{
					"paint": "blue",
					"name": "синий",
					"hex": "#317ED4"
				},
				{
					"paint": "green",
					"name": "зелёный",
					"hex": "#2BC280"
				},
				{
					"paint": "orange",
					"name": "оранжевый",
					"hex": "#FFA53C"
				},
				{
					"paint": "black",
					"name": "чёрный",
					"hex": "#121212"
				},
				{
					"paint": "yellow",
					"name": "жёлтый",
					"hex": "#E8C547"
				},
				{
					"paint": "purple",
					"name": "фиолетовый",
					"hex": "#6A5BC4"
				},
				{
					"paint": "teal",
					"name": "бирюзовый",
					"hex": "#2FA3A0"
				},
				{
					"paint": "wine",
					"name": "бордовый",
					"hex": "#87263D"
				}
			]
		},
		"en": {
			"name": "Hatchback",
			"texts": {
				"start": "Start race",
				"no_runs": "Start race",
				"colour": "Color",
				"record": "Record",
				"runs": "Races 3 of 3"
			},
			"paints": [
				{
					"paint": "red",
					"name": "red",
					"hex": "#ED4621"
				},
				{
					"paint": "white",
					"name": "white",
					"hex": "#FFFFFF"
				},
				{
					"paint": "silver",
					"name": "silver",
					"hex": "#CACACA"
				},
				{
					"paint": "blue",
					"name": "blue",
					"hex": "#317ED4"
				},
				{
					"paint": "green",
					"name": "green",
					"hex": "#2BC280"
				},
				{
					"paint": "orange",
					"name": "orange",
					"hex": "#FFA53C"
				},
				{
					"paint": "black",
					"name": "black",
					"hex": "#121212"
				},
				{
					"paint": "yellow",
					"name": "yellow",
					"hex": "#E8C547"
				},
				{
					"paint": "purple",
					"name": "purple",
					"hex": "#6A5BC4"
				},
				{
					"paint": "teal",
					"name": "turquoise",
					"hex": "#2FA3A0"
				},
				{
					"paint": "wine",
					"name": "burgundy",
					"hex": "#87263D"
				}
			]
		},
		"kk": {
			"name": "Хэтчбек",
			"texts": {
				"start": "Жарысты бастаңыз",
				"no_runs": "Жарысты бастаңыз",
				"colour": "Түс",
				"record": "Жазба",
				"runs": "3 / 3 жарыс"
			},
			"paints": [
				{
					"paint": "red",
					"name": "қызыл",
					"hex": "#ED4621"
				},
				{
					"paint": "white",
					"name": "ақ",
					"hex": "#FFFFFF"
				},
				{
					"paint": "silver",
					"name": "күміс",
					"hex": "#CACACA"
				},
				{
					"paint": "blue",
					"name": "көк",
					"hex": "#317ED4"
				},
				{
					"paint": "green",
					"name": "жасыл",
					"hex": "#2BC280"
				},
				{
					"paint": "orange",
					"name": "апельсин",
					"hex": "#FFA53C"
				},
				{
					"paint": "black",
					"name": "қара",
					"hex": "#121212"
				},
				{
					"paint": "yellow",
					"name": "сары",
					"hex": "#E8C547"
				},
				{
					"paint": "purple",
					"name": "күлгін",
					"hex": "#6A5BC4"
				},
				{
					"paint": "teal",
					"name": "көгілдір",
					"hex": "#2FA3A0"
				},
				{
					"paint": "wine",
					"name": "бургундия",
					"hex": "#87263D"
				}
			]
		}
	}[lang]
	return {
		"cars": [{"id": "hatch", "name": localized.name, "paints": localized.paints}],
		"texts": localized.texts, "record": 4387, "can_start": true,
	}
