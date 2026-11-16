-- NPC lines. English now; add a `th` table with the same keys to localise later.
local Dialogue = {}

Dialogue.en = {
	customer_wait = {
		"Is that my food? I'm starving!", "Extra spicy please, no veggies!", "Over here, rider!",
		"I ordered ages ago...", "This food smells amazing!", "Hope it's still hot!",
	},
	customer_good = {
		"Thanks! Five stars for you!", "So fast! You're the best.", "This food smells amazing!",
		"Perfect, keep the change!", "Khop khun der!", "Sep lai! Thank you!",
	},
	customer_ok = { "Thanks.", "Okay, thank you.", "A bit late, but fine.", "Got it, thanks." },
	customer_bad = { "It's cold...", "What took you so long?", "My soup is spilled!", "Not happy about this." },
	customer_rain = { "It's raining! Drive carefully!", "You came in this rain? Here's a tip.", "Thank you for braving the storm!" },
	passenger_pickup = {
		"Hi! Let's go.", "Hurry up! I'm late for class!", "To the destination, please.",
		"Nice ride!", "Sawasdee! Thanks for coming.", "Can you take the quick way?",
	},
	passenger_ride = {
		"Khon Kaen traffic, eh?", "It's raining! Drive carefully!", "Have you tried the som tam near the lake?",
		"I love the night market here.", "Slow down a little, please!", "The lake looks beautiful today.",
		"My friend drives for GoDash too.", "Is this your own vehicle?",
	},
	passenger_scared = { "Whoa! Careful!", "Hey, watch the road!", "I want to arrive alive!", "Too fast!" },
	passenger_good = { "Thanks for the ride!", "Smooth driving. Five stars!", "That was quick, thank you!", "See you around!" },
	passenger_ok = { "Thanks.", "Okay, bye.", "Here's the fare." },
	passenger_bad = { "Never again...", "That was rough.", "You drive like a maniac!" },
	staff_ready = { "Order's ready!", "Here you go, drive safe!", "Hot and fresh!", "One GoDash order, coming up!" },
	staff_idle = { "Welcome! What would you like?", "Sawasdee kha!", "Best food in Khon Kaen!", "Hungry? Take a look." },
	shopkeeper = { "Welcome!", "Take your time.", "Everything's fresh today.", "Need anything else?" },
	farmer = { "Good soil this year.", "Water them every day!", "Rain is coming, I can feel it.", "Market prices change daily, check your phone." },
	pedestrian = {
		"Sawasdee!", "Nice bike!", "Hot today, isn't it?", "Are you a GoDash rider?", "Have you eaten yet?",
		"Careful on Mittraphap Road.", "The night market opens soon.", "Beautiful evening.", "I'm off to the lake.",
		"Rain again? Mai pen rai.",
	},
	pedestrian_rain = { "I forgot my umbrella!", "So much rain!", "Run for cover!" },
}

function Dialogue.line(key: string, rng: Random?, lang: string?): string
	local t = (Dialogue :: any)[lang or "en"] or Dialogue.en
	local list = t[key] or Dialogue.en[key]
	if not list then return "..." end
	local r = rng or Random.new()
	return list[r:NextInteger(1, #list)]
end

return Dialogue
