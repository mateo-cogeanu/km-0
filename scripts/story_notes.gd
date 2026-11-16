extends RefCounted
## Everything written down along the road, in one place. Keys are note ids; the
## world places each note with note_item.gd. "len_last" is the page that tells
## you the way out.

const NOTES := {
	"len_shift": {
		"title": "Note on the workbench",
		"style": "paper",
		"text": "Gone for parts at the first garage. Back by six.\n\nRadio's on channel 4 if you need me. Ruth's on the desk tonight.\n\n— Len",
	},
	"len_log": {
		"title": "Len's notebook",
		"style": "notebook",
		"text": "MON  Wayside — 2 batteries, fan belt. Ruth says hi.\nTUE  Tower — Mick's gate key again. Left it under the drum.\nWED  Quiet. Radio playing up at night.\n\nTHU  Heard my own voice on channel 4. Asking if anybody was there. I hadn't said a thing.\n\nTHU  It said the kettle's on. At the house at the end of the road. In MY voice.\n\nI'm not going.",
	},
	"len_last": {
		"title": "Len's notebook, last page",
		"style": "notebook",
		"text": "If anyone finds this.\n\nDon't follow the radio. Don't go to the house.\n\nGo back. Past the workshop, past where the road starts. Keep going into the desert and don't stop, whatever you hear behind you.\n\nThat's the only way it can't follow. I'm sure of it.\n\nI'm going now. If you hear me on the radio after tonight, it isn't me.",
	},
	"ruth_postcard": {
		"title": "Postcard",
		"style": "postcard",
		"text": "Mum,\n\nThe job's fine. Quiet out here, nothing but the road and the radio. Len brings us tea when he comes through.\n\nThe radio does funny things at night. Sometimes I hear myself on it, saying things I haven't said yet. The others laugh about it.\n\nLove you. Home Sunday.\n— Ruth",
	},
	"mick_scrawl": {
		"title": "Torn page by the radio",
		"style": "paper",
		"text": "COUNTY —\n\nI only called in ONCE.\n\nSix o'clock, all clear, that's all I said. I heard it go out again at five past. And again. Same cough and everything.\n\nWho is using my voice?\n\n— Mick",
	},
	"house_photo": {
		"title": "Polaroid",
		"style": "photo",
		"text": "A photo of a house at the end of a road, taken from the porch at night. The lights are on.\n\nOn the wall beside the window, something pale and flat is pressed against the plaster, looking straight at the camera.\n\nIt is smiling.\n\nWritten on the back: \"it was there the whole time I was knocking\"",
	},
	"county_log": {
		"title": "County desk log",
		"style": "sheet",
		"text": "EAST ROAD — EVENING\n\n18:00  Roll call. No answer: Len, Ruth, June, Alan, Rose.\n18:02  Mick. All clear.\n18:05  Mick. All clear. (Same words.)\n18:07  Mick. All clear. (Same words. Same cough.)\n18:40  Ruth answered. Said Len hasn't called yet. She said that two days ago.\n19:15  Someone's on channel 4 saying the kettle's on, at the house where the pavement runs out.\n19:30  Going out there myself. Somebody has to.",
	},
	"stranger_wall": {
		"title": "Scratched into the table",
		"style": "paper",
		"text": "DON'T ANSWER IT\n\nIT LEARNS\n\nIT LEARNS YOUR VOICE",
	},
	"county_badge": {
		"title": "Lanyard on the stairs",
		"style": "photo",
		"text": "A plastic ID card on a frayed lanyard.\n\nCOUNTY ROADS — DISPATCH\nNight desk\n\nThe photo has been scratched out.",
	},
}

## Notes read on this trip, saved with it.
static var read := {}
