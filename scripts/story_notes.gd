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
		"text": "MON  Wayside — 2 batteries, fan belt. Ruth says hi.\nTUE  Tower — Mick's gate key again. Left it under the drum.\nWED  Quiet. Radio playing up at night.\n\nTHU  Heard my own voice on channel 4. Asking if anybody was there. I hadn't said a thing.\n\nTHU  It said the kettle's on. At the house at the end of the road. In MY voice.\n\nMick reckons the road doesn't end until it's had a good listen to you, and you to it. A few stations, a couple of nights out here. Then one morning the house is just there.\n\nI'm not going.",
	},
	"len_last": {
		"title": "Len's notebook, last page",
		"style": "notebook",
		"text": "If anyone finds this.\n\nDon't follow the radio. Don't go to the house. There is a way out.\n\nI've written it down in pieces and left them in different places, so it can't hear all of it at once.\n\nFirst piece: go back. Past the workshop, past where the road starts.\n\nThe next piece is with Mick, at the tower.\n\nIf you hear me on the radio after tonight, it isn't me.",
	},
	"len_page_tower": {
		"title": "Torn page, Len's handwriting",
		"style": "paper",
		"text": "Second piece.\n\nKeep going into the desert. Further than you'd think. Twelve kilometres. More.\n\nFill the tank. Bring water. Bring tools.\n\nThe last piece is with the man in the cabin, back past the workshop. He won't remember me.\n\n— L",
	},
	"len_page_cabin": {
		"title": "Folded page, Len's handwriting",
		"style": "paper",
		"text": "Last piece.\n\nWhatever you hear behind you, don't stop and don't answer.\n\nIf the car gives out, fix it fast. It's slow, but it doesn't get tired, and it will be right behind you.\n\nIf it catches you, you're the next voice on the radio.\n\n— Len",
	},
	"county_car": {
		"title": "Note on the passenger seat",
		"style": "paper",
		"text": "COUNTY ROADS — DISPATCH\n\nIt's in the walls. I can hear it moving in them.\n\nIf I don't come back out: don't go in after me.\n\nPetrol on every wall. All four sides. Then light it.\n\nThere's a can in the boot.",
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
	"wreck_county": {
		"title": "Notice on the dashboard",
		"style": "sheet",
		"text": "COUNTY ROADS — NOTICE TO DRIVERS\n\nCheck in at every station.\nKeep the tank above a quarter. Stations are a kilometre apart and not all of them have petrol.\nDo not leave the road after dark.\nIf you hear your own voice on the radio, do not answer it.\nIf you see anyone sitting out in the desert, keep driving. Do not stop. Do not look for long.",
	},
	"wreck_rose": {
		"title": "Postcard on the seat",
		"style": "postcard",
		"text": "Dad,\n\nSaw someone out in the desert today. Just sitting, way off from the road, watching the car go by. I waved.\n\nI looked back at the road for a second, and when I looked again there was nobody there. Nothing to hide behind for miles.\n\nNobody lives out here, do they?\n\n— Rose",
	},
	"wreck_june": {
		"title": "Note under the wiper",
		"style": "paper",
		"text": "To whoever's next,\n\nNothing wrong with the car. I stopped because it was sitting in the road ahead of me, in the headlights, and it wouldn't move.\n\nI looked at it and looked at it and then it just wasn't there.\n\nI'm walking back to the last station. Don't wait for me. Don't stare at it.\n\n— June",
	},
	"wreck_tape": {
		"title": "Cassette in the deck, label written out",
		"style": "sheet",
		"text": "RADIO LOG — EAST ROAD\n\nCOUNTY: East road, check in.\nALAN: Alan, station four. All clear.\nCOUNTY: Copy, Alan.\n[static]\nALAN: Alan, station four. All clear.\nCOUNTY: Alan, you just said that.\nALAN: I haven't said anything. I'm sat in the car. I'm looking at the radio.\n[static]\nALAN: Alan, station four. All clear.",
	},
	"wreck_alan": {
		"title": "Alan's road map",
		"style": "notebook",
		"text": "A map of the east road, marked up in pencil. Every station circled, with a tally of nights beside it.\n\nPast where the paper runs out, someone has drawn a small house in ink, pressing so hard the pen went through.\n\nIn the margin:\n\nIt's only ever where you're not looking. You can't keep looking at it. The longer you look the worse it gets.",
	},
	"station_wrecked": {
		"title": "Shift log, trodden into the dirt",
		"style": "sheet",
		"text": "EAST ROAD — NIGHT SHIFT\n\n01:50  All quiet. Checked in.\n02:10  Something on the roof.\n02:14  It's walking round the outside. It stops when I stop.\n02:31  It knocked. Three times. The way Len knocks.\n02:32  Len's on the radio saying he's outside and could I open up.\n\nI'm not opening the door.",
	},
	"wreck_dash": {
		"title": "Scratched into the dashboard",
		"style": "paper",
		"text": "IT WAS SITTING IN THE BACK SEAT\n\nI LOOKED IN THE MIRROR TOO LONG",
	},
}

## Notes read on this trip, saved with it.
static var read := {}
