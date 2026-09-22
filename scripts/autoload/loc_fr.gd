extends RefCounted
## The French table.
##
## English is the key (see `loc.gd`), so a row is `"the English as it is printed": "le français"`.
## Rows are grouped by the file they come from, which is how this is maintained: a new sentence in
## the interface is a new row here, and a sentence with no row is simply English that has not been
## translated *yet* rather than a hole in the screen.
##
## Two things to keep in mind when adding rows:
##
##   * **Keep the placeholders, and only the placeholders.** `%s`, `%d` and `%.1f` may be moved
##     around a French sentence — that is why the template is translated before the values go in —
##     but `%%` is a literal per cent and must survive as `%%`.
##   * **Match the source character for character.** The `·` separators, the trailing full stop,
##     the capital letters: the lookup is exact, and a row that does not match is a row that does
##     nothing at all, quietly.

const TABLE: Dictionary = {
	# ------------------------------------------------------------------ the control strip
	"WASD move · Shift run · Space jump · click to strike · Q dash · C cultivate · B break through":
		"Déplacements ZQSD · Maj course · Espace saut · clic frapper · Q esquive · C cultiver · B percée",
	"E talk to the elder · 1/2/3 drill the body · X qi pressure · T recall · Tab settings · V stats":
		"E parler à l'ancien · 1/2/3 entraîner le corps · X pression de qi · T rappel · Tab réglages · V stats",
	"   ·   click to look around": "   ·   cliquez pour regarder autour",
	"   ·   CAMP WARDS — nothing here will follow you in":
		"   ·   SCEAUX DU CAMP — rien ne vous suivra ici",
	"   ·   MEDITATING — press C to stand": "   ·   MÉDITATION — appuyez sur C pour vous lever",
	"   ·   DASH ready": "   ·   ESQUIVE prête",
	"   ·   dash cooling": "   ·   esquive en recharge",
	"Click (or F) to strike — posts raise ATTACK, raiders drop crystals.":
		"Cliquez (ou F) pour frapper — les poteaux montent l'ATTAQUE, les pillards lâchent des cristaux.",
	"Tap 1, 2 or 3 to drill BODY: it costs blood, not qi, and widens your HP cap.":
		"Touches 1, 2 ou 3 pour entraîner le CORPS : ça coûte du sang, pas du qi, et élargit votre plafond de PV.",
	# The interact prompt. One line for the whole world, and the reason it exists is that the
	# tower's door was a conversation nobody could find the handle for.
	"E — %s": "E — %s",
	"speak with %s": "parler à %s",
	"speak with %s — %s": "parler à %s — %s",
	"the tower's door": "la porte de la tour",
	"take the stair": "prendre l'escalier",
	"go up": "monter",
	"the floor is not clear yet": "l'étage n'est pas encore net",
	"Qi Pressure — unavailable": "Pression de Qi — indisponible",
	"Qi Pressure — needs %.0f QI held (you have %.0f)":
		"Pression de Qi — demande %.0f QI détenu (vous en avez %.0f)",

	# ------------------------------------------------------------------ settings and panels
	"SETTINGS": "RÉGLAGES",
	"TRAINING CAPS": "PLAFONDS D'ENTRAÎNEMENT",
	"INTERFACE SIZE": "TAILLE DE L'INTERFACE",
	"AURA": "AURA",
	"LANGUAGE": "LANGUE",
	"VOICES": "VOIX",
	"On": "Activées",
	"Off": "Coupées",
	"Sliders cap at what you have earned. Train to raise the cap.":
		"Les curseurs s'arrêtent à ce que vous avez gagné. Entraînez-vous pour lever le plafond.",
	"Smaller": "Plus petit",
	"Bigger": "Plus grand",
	"Reset progress": "Effacer la progression",
	"Press Reset again to erase all progression.":
		"Appuyez encore sur Effacer pour tout perdre.",
	"Progress recorded.": "Progression enregistrée.",
	"Time holds while the panel is open.": "Le temps s'arrête pendant que le panneau est ouvert.",
	"Esc to step away": "Échap pour s'éloigner",
	"Step away": "S'éloigner",
	"Show every stat (V)": "Voir toutes les statistiques (V)",
	"Fold the stat readout away (V)": "Replier le relevé de statistiques (V)",
	"Show the map": "Afficher la carte",
	"Fold the map away": "Replier la carte",
	"THE ELDER'S SHELF": "L'ÉTAGÈRE DE L'ANCIEN",
	"Hand it in": "Le remettre",
	"Nothing left to teach": "Plus rien à enseigner",
	"Nothing to hand in": "Rien à remettre",
	"Not finished yet": "Pas encore fini",
	"All tasks complete": "Toutes les tâches accomplies",
	"You have finished every task he knows how to set.":
		"Vous avez accompli tout ce qu'il sait demander.",
	"The elder has nothing left to set.": "L'ancien n'a plus rien à demander.",
	"Every stat has become everything it was going to become.":
		"Chaque statistique est devenue tout ce qu'elle devait devenir.",
	"Every threshold in this stat is behind you.":
		"Tous les paliers de cette statistique sont derrière vous.",
	"No technique yet. Every stat turns into something at a multiple of its":
		"Pas encore de technique. Chaque statistique se transforme à un multiple de son",
	"nothing yet": "rien encore",
	"locked until": "bloqué jusqu'à",
	"a reward": "une récompense",
	"all it can give": "tout ce qu'elle peut donner",
	"every technique held": "chaque technique détenue",
	"how full": "remplissage",
	"things this body can do": "ce que ce corps sait faire",
	"INSIGHT FULL — press B to break through": "INTUITION PLEINE — B pour percer",
	"sold out": "épuisé",
	"Sold out": "Épuisé",

	# ------------------------------------------------------------------ the statistics
	"ATTACK": "ATTAQUE",
	"DEFENSE": "DÉFENSE",
	"SPEED": "VITESSE",
	"BODY": "CORPS",
	"Weathering damage": "Encaisser les coups",
	"Striking the training posts": "Frapper les poteaux d'entraînement",
	"Running (hold Shift)": "Courir (Maj maintenu)",
	"Pushups, squats and standing stance": "Pompes, squats et posture debout",
	"Toughening up under damage": "Endurcir le corps sous les coups",
	"1 xp per point of damage dealt to a post": "1 xp par point de dégât infligé à un poteau",
	"1 xp per metre run (hold Shift)": "1 xp par mètre couru (Maj maintenu)",
	"1 xp per rep of physical training": "1 xp par répétition d'entraînement physique",
	"1 xp per jump, scaled by how high you jumped": "1 xp par saut, selon la hauteur",
	"0.5 xp per point of damage weathered": "0,5 xp par point de dégât encaissé",
	"2 xp per point of damage weathered": "2 xp par point de dégât encaissé",
	"1 xp per 0.5 QI spent meditating": "1 xp par 0,5 QI dépensé en méditation",
	"Thick Skin": "Peau Épaisse",
	"Iron Skin": "Peau de Fer",
	"Jade Skin": "Peau de Jade",
	"Iron Bones": "Os de Fer",
	"Second Wind": "Second Souffle",
	"Deep Well": "Puits Profond",
	"Dantian Bell": "Cloche du Dantian",
	"Blood Boil": "Sang Bouillant",
	"Sky Step": "Pas du Ciel",
	"Cloud Step": "Pas des Nuages",
	"Qi Bolt": "Trait de Qi",
	"Iron Stance": "Posture de Fer",
	"Refining it while meditating": "L'affiner en méditation",
	"Out of a fight, wounds close three times as fast.":
		"Hors combat, les blessures se referment trois fois plus vite.",
	"Blows land eight per cent softer on a body that has been through a few.":
		"Les coups portent huit pour cent plus doux sur un corps qui en a vu.",
	"Everything is eight per cent softer on a body that has been through everything.":
		"Tout porte huit pour cent plus doux sur un corps qui a tout traversé.",
	"A trained hide over a trained frame: another twelve per cent off every blow.":
		"Une peau entraînée sur une charpente entraînée : encore douze pour cent en moins.",
	"Some of every blow you take is given back to the one who threw it.":
		"Une part de chaque coup reçu revient à celui qui l'a porté.",
	"A shell of qi eats one blow every eighteen seconds, out of the dantian.":
		"Une coque de qi absorbe un coup toutes les dix-huit secondes, prise sur le dantian.",
	"Once every ninety seconds, a killing blow leaves you standing at a quarter.":
		"Toutes les quatre-vingt-dix secondes, un coup fatal vous laisse debout à un quart.",
	"Blows no longer move you.": "Les coups ne vous déplacent plus.",
	"Falls hurt half as much and the safe drop is two metres deeper.":
		"Les chutes font moitié moins mal et la chute sûre gagne deux mètres.",
	"You get up twice as fast and do not slide half as far.":
		"Vous vous relevez deux fois plus vite et glissez deux fois moins loin.",
	"Below a third of your health, your blows land a quarter harder.":
		"Sous un tiers de vie, vos coups portent un quart plus fort.",
	"One blow in five lands crushing, for double.": "Un coup sur cinq écrase, pour le double.",
	"A deep well behind a hard wall: the jade shell comes back twice as fast.":
		"Un puits profond derrière un mur dur : la coque de jade revient deux fois plus vite.",
	"Qi Pressure costs a third less to hold.": "La Pression de Qi coûte un tiers de moins à tenir.",
	"A landing from six metres staggers everything within three and a half.":
		"Une chute de six mètres fait vaciller tout ce qui est à trois mètres et demi.",
	"The first three quarters of a second of a sprint is a third faster.":
		"Les trois premiers quarts de seconde d'un sprint sont un tiers plus rapides.",
	"Steeper ground stays runnable, and you are an eighth quicker than training alone.":
		"Les pentes raides restent courantables, et vous êtes un huitième plus rapide.",
	"One more jump in the air than training alone would allow.":
		"Un saut de plus en l'air que l'entraînement seul ne permet.",
	"Hold jump in the air and walk on it. It is paid for the whole time.":
		"Maintenez saut en l'air et marchez dessus. Ça se paie en continu.",
	"R throws a ball of your own aura at what you are looking at, for a ":
		"R lance une bille de votre propre aura sur ce que vous visée, pour un ",
	"twentieth of the dantian.": "vingtième du dantian.",
	"A new cultivator awakens.": "Un nouveau cultivateur s'éveille.",
	"Vitality and qi fully restored.": "Vitalité et qi entièrement restaurés.",
	"Progression wiped. A new cultivator awakens.":
		"Progression effacée. Un nouveau cultivateur s'éveille.",
	"Save file is not valid JSON; starting fresh.":
		"Le fichier de sauvegarde n'est pas un JSON valide ; on repart à zéro.",
	"nothing worn": "rien de porté",

	# ------------------------------------------------------------------ training drills
	"Iron Stance.": "Posture de Fer.",
	"Horse stance. Slow and stubborn, and it thickens the skin you hide behind.":
		"Posture du cheval. Lente et têtue, elle épaissit la peau qui vous abrite.",
	"Pure constitution. Costs the most blood and trains the most body.":
		"Constitution pure. Coûte le plus de sang et entraîne le plus le corps.",
	"Cheaper per rep, and the legs earn a little of the jump with them.":
		"Moins cher par répétition, et les jambes y gagnent un peu du saut.",
	"Nothing left in the tank. The set ends.": "Plus rien dans le réservoir. La série s'arrête.",

	# ------------------------------------------------------------------ the map and its legend
	"Village / tower": "Village / tour",
	"Raider camp": "Camp de pillards",
	"Camp wards": "Sceaux du camp",
	"camp wards (safe)": "sceaux du camp (sûr)",
	"Site you found": "Site découvert",
	"The elder": "L'ancien",
	"a reward is waiting": "une récompense attend",
	"there is something here for you": "il y a quelque chose ici pour vous",
	"50 m": "50 m",

	# ------------------------------------------------------------------ the villages
	"the road's start": "le début de la route",
	"the forge": "la forge",
	"keeper of the village": "gardien du village",
	"trader": "marchand",
	"physician": "guérisseuse",
	"the board": "le tableau",
	"the tower's foot": "le pied de la tour",
	"Hollowmere — a well, four roofs, and a palisade somebody mended twice.":
		"Hollowmere — un puits, quatre toits, et une palissade que quelqu'un a réparée deux fois.",
	"Stonewatch — hammer, smoke, and a palisade of new-cut timber.":
		"Stonewatch — marteau, fumée, et une palissade de bois fraîchement coupé.",
	"Towerfall — the spire's shadow lies over the whole square, and nobody looks up.":
		"Towerfall — l'ombre de la flèche couvre toute la place, et personne ne lève les yeux.",
	"You came down the road, so you are somebody's news. Sit. Nothing here is in a hurry.":
		"Vous arrivez par la route, alors vous êtes une nouvelle pour quelqu'un. Asseyez-vous. Rien n'est pressé ici.",
	"Mind the sparks. Everything here is either being made or being repaired.":
		"Attention aux étincelles. Ici tout est en train d'être fait ou réparé.",
	"You have seen it. Everybody who arrives has seen it. The question is why you came anyway.":
		"Vous l'avez vu. Tous ceux qui arrivent l'ont vu. La question, c'est pourquoi vous êtes venu quand même.",
	"a stranger": "un inconnu",
	"known by sight": "reconnu de vue",
	"talked about": "dont on parle",
	"You are somebody's rumour now, you know.": "Vous êtes une rumeur, maintenant, vous savez.",
	"Somebody said your name in the square and nobody asked who.":
		"Quelqu'un a dit votre nom sur la place et personne n'a demandé qui.",
	"They say your name now, further down the road. They say it carefully.":
		"Ils disent votre nom maintenant, plus loin sur la route. Ils le disent prudemment.",
	"They have stopped asking what you want and started asking what you need.":
		"Ils ont cessé de demander ce que vous voulez et commencent à demander ce qu'il vous faut.",
	"They look at you the way people look at weather coming in.":
		"Ils vous regardent comme on regarde le temps qui arrive.",
	"Elder Mei": "Ancienne Mei",
	"Tao the Pedlar": "Tao le Colporteur",
	"Grandmother Nuo": "Grand-mère Nuo",
	"Watchman Gu": "Gu la Vigie",
	"Little Shen": "Petit Shen",
	"Forgemaster Du": "Maître Forgeron Du",
	"Physician Rao": "Médecin Rao",
	"Captain Zhu": "Capitaine Zhu",
	"Sergeant Ou": "Sergent Ou",
	"Sister Lan": "Sœur Lan",
	"Scholar Yun": "Érudit Yun",
	"Old Wen": "Vieil Wen",
	"Iron Auntie": "Tante de Fer",
	"Warden Bai": "Gardien Bai",
	"Apprentice Fen": "Apprenti Fen",
	"Forgemaster Du — the anvil": "Maître Forgeron Du — l'enclume",
	"Scholar Yun has been reading the same three pages for nine years.":
		"L'érudit Yun relit les mêmes trois pages depuis neuf ans.",
	"Worn now.": "Porté en ce moment.",
	"Yours, and not on.": "À vous, et pas porté.",
	"wear it": "le porter",
	"take it": "le prendre",
	"Not enough crystals for that one.": "Pas assez de cristaux pour celui-là.",
	"Not enough crystals for another.": "Pas assez de cristaux pour en reprendre un.",
	"Not enough of what it is made of, or not enough crystals.":
		"Pas assez de matière, ou pas assez de cristaux.",
	"One in the belt.": "Un dans la ceinture.",
	"Nothing on the board": "Rien au tableau",
	"Nothing to forge yet": "Rien à forger pour l'instant",
	"Nothing of yours to settle there.": "Rien à vous à régler là-bas.",
	"Nothing in the valley has ever reached the hundredth floor.":
		"Rien dans la vallée n'a jamais atteint le centième étage.",
	"That name cannot be taken from here.": "Ce nom ne peut pas être pris d'ici.",
	"The clerk will have new names by tomorrow.": "Le greffier aura de nouveaux noms demain.",
	"Buy something to wear first — the traders at the other villages keep the pieces.":
		"Achetez d'abord quelque chose à porter — les marchands des autres villages gardent les pièces.",
	"Stand still and let Elder Mei tell you what you have walked into.":
		"Restez immobile et laissez l'Ancienne Mei vous dire dans quoi vous venez d'entrer.",
	"Carry Mei's letter to Warden Bai in Stonewatch, past the ward.":
		"Portez la lettre de Mei au Gardien Bai à Stonewatch, au-delà du sceau.",
	"Du will work for four Hide Scrap. The near raiders carry them.":
		"Du travaillera pour quatre Morceaux de Peau. Les pillards proches en portent.",
	"Du has finished a commission for Towerfall. Carry it there.":
		"Du a fini une commande pour Towerfall. Portez-la là-bas.",
	"Come back from the tenth floor of the tower alive.":
		"Revenez vivant du dixième étage de la tour.",
	"The last champion is standing on the last spirit zone. Take it from it.":
		"Le dernier champion se tient sur la dernière zone spirituelle. Prenez-la-lui.",
	"There is a place up the road nobody tends and everybody knows. Find it.":
		"Il y a un endroit en haut de la route que personne n'entretient et que tout le monde connaît. Trouvez-le.",
	"Ten floors": "Dix étages",
	"The top of the stair": "Le haut de l'escalier",
	"The Standing Circle": "Le Cercle Debout",
	"The Ninth's ground": "Le terrain du Neuvième",
	"The blade goes south": "La lame part vers le sud",
	"What the valley is": "Ce qu'est la vallée",
	"Why the tower is here": "Pourquoi la tour est là",
	"Scales for the forge": "Écailles pour la forge",
	"Something worth wearing": "Quelque chose qui vaut la peine d'être porté",
	"A sealed letter": "Une lettre scellée",
	"Mei's sealed letter": "La lettre scellée de Mei",
	"A heavier purse": "Une bourse plus lourde",
	"Du's commission, wrapped in oilcloth": "La commande de Du, en toile huilée",
	"It is down. Collect.": "Il est tombé. Allez le chercher.",
	"a step finished": "une étape terminée",
	"is down, then bring the proof back here.": "est tombé, alors rapportez la preuve ici.",
	"The gate goes back up, and the first stall opens before the last post is in.":
		"La porte se relève, et le premier étal ouvre avant que le dernier poteau soit planté.",

	# ------------------------------------------------------------------ the people
	"Master Ren": "Maître Ren",
	"Xia the Firekeeper": "Xia la Gardienne du Feu",
	"Old Bo": "Vieux Bo",
	"The Tower": "La Tour",
	"The Tower's Door": "La Porte de la Tour",
	"You are new here. It is in the shoulders.":
		"Tu es nouveau ici. Ça se voit aux épaules.",
	"You have grown since last I looked. It shows in how you stand.":
		"Tu as grandi depuis la dernière fois. Ça se voit à ta façon de te tenir.",
	"Not today": "Pas aujourd'hui",
	"Another time": "Une autre fois",
	"Not yet": "Pas encore",
	"I will live": "Je survivrai",
	"Say it again": "Redis-le",
	"Hand it over": "Remets-le",
	"What did I do for you?": "Qu'est-ce que j'ai fait pour vous ?",
	"What names?": "Quels noms ?",
	"What have you got?": "Qu'est-ce que vous avez ?",
	"Show me your shelf": "Montrez-moi votre étal",
	"Then show me the pills": "Alors montrez-moi les pilules",
	"Put something on the anvil": "Mettre quelque chose sur l'enclume",
	"Tell me what it is": "Dis-moi ce que c'est",
	"He should have his book": "Il devrait récupérer son livre",
	"Then let it stay lost": "Alors laisse-le perdu",
	"The road is worth more than they are": "La route vaut plus qu'eux",
	"Let them keep their fire": "Laissez-leur leur feu",
	"Teach me the heavier hand": "Enseigne-moi la main plus lourde",
	"Teach me the deeper breath": "Enseigne-moi le souffle plus profond",
	"Take the stair from the ground floor": "Prendre l'escalier depuis le rez-de-chaussée",
	"Go down one floor": "Descendre d'un étage",
	"Stay on this landing": "Rester sur ce palier",
	"Leave the tower": "Quitter la tour",
	"A step finished is a step paid.": "Une étape finie est une étape payée.",
	"All of them, at once.": "Toutes, d'un coup.",
	"Bring the material and the crystals and it comes out better.":
		"Apportez la matière et les cristaux et ça sortira meilleur.",
	"ATTACK cap permanently +8. The breath is closed to you.":
		"Plafond d'ATTAQUE +8 pour toujours. Le souffle vous est fermé.",
	"QI cap permanently +60. The hand is closed to you.":
		"Plafond de QI +60 pour toujours. La main vous est fermée.",
	"Those raiders will never raise a hand to you again. DEFENSE cap +6.":
		"Ces pillards ne lèveront plus jamais la main sur vous. Plafond de DÉFENSE +6.",
	"The nearest raider camp is cleared for good. +45 crystals.":
		"Le camp de pillards le plus proche est nettoyé pour de bon. +45 cristaux.",
	"Burn their camp with them in it, or take the road past it and let them live?":
		"Brûler leur camp avec eux dedans, ou prendre la route et les laisser vivre ?",
	"Ninety-nine floors you have not seen, and the ones you have are empty.":
		"Quatre-vingt-dix-neuf étages que vous n'avez pas vus, et ceux que vous connaissez sont vides.",
	"Ever downward is free, and a cleared floor stays clear.":
		"Descendre est toujours libre, et un étage nettoyé reste nettoyé.",
	"The way up is open.": "Le chemin vers le haut est ouvert.",
	"You keep the depth you have taken. You lose nothing but the climb.":
		"Vous gardez la profondeur prise. Vous ne perdez que l'ascension.",
	"The door does not move. It is waiting for a body with more behind it than it has in front of it.":
		"La porte ne bouge pas. Elle attend un corps qui a plus derrière lui que devant.",
	"The door does not answer.": "La porte ne répond pas.",
	"There is nothing above this one that will let you in.":
		"Rien au-dessus ne vous laissera entrer.",
	"There is nothing below you but the ground.": "Il n'y a rien sous vous que le sol.",
	"Then there is nothing to ask.": "Alors il n'y a plus rien à demander.",
	"Not yet — there is more to do before that.": "Pas encore — il reste des choses à faire.",
	"You cannot cover the fee, and she does not work on credit.":
		"Vous ne pouvez pas payer, et elle ne travaille pas à crédit.",
	"You cannot cover the price, and nobody in the valley works on credit.":
		"Vous ne pouvez pas payer, et personne dans la vallée ne travaille à crédit.",
	"It is standing. Whatever you were about to pay for, it was not that.":
		"Elle est debout. Quoi que vous alliez payer, ce n'était pas ça.",
	"They will not start it without the price in hand.":
		"Ils ne commenceront pas sans le prix en main.",
	"He carries other people's accounts.": "Il porte les comptes des autres.",
	"He is the one who asks what your hands are for.":
		"C'est lui qui demande à quoi servent vos mains.",
	"She has watched every camp smoke from up here.":
		"D'ici, elle a vu fumer tous les camps.",
	"Nobody has anything for sale until it is standing again.":
		"Personne n'a rien à vendre tant qu'elle n'est pas relevée.",

	# ------------------------------------------------------------------ the tasks
	"Find your feet": "Trouver ses marques",
	"The long road": "La longue route",
	"Blood on the road": "Du sang sur la route",
	"What is over the hill": "Ce qu'il y a derrière la colline",
	"Deep water": "Eau profonde",
	"Sit still until it moves": "Rester immobile jusqu'à ce que ça bouge",
	"A realm is not rushed.": "Un royaume ne se presse pas.",
	"you can walk": "vous pouvez marcher",
	"you can dash": "vous pouvez esquiver",
	"and a new trick": "et une nouvelle technique",
	"Every raider carries a shard or two.": "Chaque pillard porte un ou deux éclats.",
	"Shift to run. The metres count only while you are actually moving.":
		"Maj pour courir. Les mètres comptent seulement quand vous bougez vraiment.",
	"Press C to sit. A spirit zone does the same work faster.":
		"Appuyez sur C pour vous asseoir. Une zone spirituelle fait le même travail plus vite.",
	"Follow a road out of camp. Anything the map wants you to find is tall and lit.":
		"Suivez une route hors du camp. Ce que la carte veut vous faire trouver est haut et éclairé.",
	"Raiders keep to their own ground. Strike them, then step back out of reach.":
		"Les pillards restent sur leur terrain. Frappez, puis reculez hors de portée.",
	"The roads are levelled for exactly this.": "Les routes sont nivelées exactement pour ça.",
	"Jump again in mid-air once this is yours — and mind the landing.":
		"Sautez à nouveau en plein air une fois ceci à vous — et attention à l'atterrissage.",
	"Run {target} m in total.": "Courez {target} m au total.",
	"Run {target} m with Shift held. The road out of camp is the long one.":
		"Courez {target} m avec Maj maintenu. La route hors du camp est longue.",
	"Cultivate for {target} seconds in total.": "Cultivez pendant {target} secondes au total.",
	"Leave the ground {target} times.": "Quittez le sol {target} fois.",
	"Defeat {target} raiders at their camps.": "Battez {target} pillards dans leurs camps.",
	"Gather {target} crystals from the camps.": "Récoltez {target} cristaux dans les camps.",
	"Find {target} of the old places along the roads. They burn a light until you do.":
		"Trouvez {target} des vieux lieux le long des routes. Ils brûlent une lumière jusqu'à ce que vous le fassiez.",

	# ------------------------------------------------------------------ the valley's own lines
	"%s IS MARKED TONIGHT — be at the gate by %02d:00":
		"%s EST MARQUÉ CETTE NUIT — soyez à la porte avant %02dh00",
	"RAID ON %s — %d still standing": "RAID SUR %s — %d encore debout",
	"%s IS OPEN — %d crystals mends the gate":
		"%s EST OUVERT — %d cristaux pour relever la porte",
	"FLOOR %d of %d — %s": "ÉTAGE %d sur %d — %s",
	"%s — the watch holds this ground": "%s — la garde tient ce terrain",
	"WATCHED IN %s — %d crystals settles it": "SURVEILLÉ À %s — %d cristaux règlent ça",
	"%s IN %s — %d crystals, or the bars": "%s À %s — %d cristaux, ou les barreaux",
	"%d wound%s — the breath comes short": "%d blessure%s — le souffle est court",
	"the tower stands at %d": "la tour se tient au %d",
	"%s  ×%.1f qi": "%s  ×%.1f qi",
	"%s · Stage %d": "%s · Palier %d",
	"%s · %s": "%s · %s",
	"Stage %d · %s · %d crystals · power %s": "Palier %d · %s · %d cristaux · puissance %s",
	"Stat gain ×%.2f": "Gain de stat ×%.2f",
	"REFINEMENT %d   ·   next in %.0fs": "RAFFINEMENT %d   ·   prochain dans %.0fs",
	"%d wounds%s — the breath comes short": "%d blessures%s — le souffle est court",
	"%s — dormant, needs stage %d": "%s — dormante, palier %d requis",
	"Crystals %d": "Cristaux %d",

	# ------------------------------------------------------------------ the tower's bands
	"The Lower Stair": "L'Escalier Bas",
	"The Ash Landing": "Le Palier des Cendres",
	"The Iron Galleries": "Les Galeries de Fer",
	"The Choking Dark": "Le Noir Étouffant",
	"The Long Ascent": "La Longue Montée",
	"The Broken Sky": "Le Ciel Brisé",
	"The Twelve Halls": "Les Douze Salles",
	"The Quiet Floors": "Les Étages Silencieux",
	"The Ninth Landing": "Le Neuvième Palier",
	"The Seat": "Le Siège",

	# ------------------------------------------------------------------ the realms
	"Body Tempering": "Trempe du Corps",
	"Qi Condensation": "Condensation du Qi",
	"Foundation Establishment": "Établissement des Fondations",
	"Core Formation": "Formation du Noyau",
	"Nascent Soul": "Âme Naissante",
	"Soul Transformation": "Transformation de l'Âme",
	"Void Refinement": "Raffinement du Vide",
	"Body Integration": "Intégration du Corps",
	"Great Ascension": "Grande Ascension",
	"Immortal Ascension": "Ascension Immortelle",
}
