# WHO BURNED THE MILL?
### Scenario 1 · Mystery · Story Bible v1.0
*"Nobody burns a village. A village burns itself, one whisper at a time."*

> **v1.1 revisions (after review):** (1) the "why Rowan" logic is now grounded in village prejudice, not coincidence; (2) Wick's alibi is plausible and must be *broken*, not merely noticed; (3) a misdirection plan so a genre-savvy player does not guess Wick on day 1 (§8, "Keeping Wick a surprise"); (4) the Moot's founding right is planted in the prologue so the finale is earned; (5) a **Deduction Board** so the player makes the connections themselves (§7); (6) the Moot is now an interactive argument, not a menu (§8, Day 12); (7) Rowan's name and pronouns are chosen by the player.

> **v1.2 (as built):** while wiring the story into the real engine, the protagonist became **Rowan Hollis**, the Hollis family's foster child who has lived in Alderbrook for ten years (the seed village already has a mill helper in that family), and "E.W." became "E." so it can point at Elspeth Dunn. Wick has known Rowan since childhood. See `02_slice_as_built.md` for the exact mapping and what is implemented.

> **DESIGNER'S EYES ONLY. This document contains every secret, twist and ending.** Players never see it. Everything here is written so it can later be loaded into the database as data (scenario, cast, clues, story beats, endings), not hard-coded.

---

## Contents
1. The pitch
2. The rules of a fair mystery
3. Rowan, the protagonist
4. The clock and the four meters
5. The cast
6. The truth (the case file)
7. The Chain of Seven and the clue catalogue
8. The story, day by day
9. The Quiet Man's engine (how the killer acts)
10. Deaths and permanent consequences
11. Endings, rewards and punishments
12. The Compass (optional guidance)
13. The Almanac (the in-game manual)
14. Difficulty and fairness
15. How this maps to the database
16. Decisions I need from you

---

# 1. The pitch

**Logline.** On the night of the third day, Tobin's Mill burns and the miller is found dead. You are Rowan, the mill helper: a stranger with a burned past, a public quarrel behind you, and your own key in the ashes. The Reeve arrives on the twelfth day to judge. Unless you find the truth, *you* are the verdict.

**What the player feels.** Hunted, then curious, then horrified, then, if they play well, powerful. The game opens as "clear my name," turns into "stop a killer," and ends as "this was never about me, and it was never only about this village."

**The three promises.**
1. **Every decision costs something.** You have three actions a day and a village that will not wait. Protecting one person means abandoning another.
2. **Every twist was fair.** After each reveal the player can scroll back through their own journal and find the clue they walked past.
3. **The ending is yours, and it is proven.** The game finishes with *The Reckoning*: the village's own causal record (the database's Ask Why), laid out link by link, showing how your small choices on day 1 became a death on day 3. No other game can show this, because no other game has a ledger that cannot lie.

**Tone.** Candlelit, cold, intimate. A small place where everybody has known everybody for forty years, which is exactly why a lie can live in it. Dark, but never gratuitous: **no child is ever harmed on screen.** The weight comes from choices, not gore.

**Why a mystery first.** It uses the engine's strongest features: fog of knowledge (you only know what you witnessed), witnesses and testimony, Ask Why on any event, delayed consequences, and rewind as a limited power.

---

# 2. The rules of a fair mystery

These are design laws. Every scene is checked against them.

1. **Every twist is foreshadowed by at least two clues**, one of them available in the first three days.
2. **Every proof has at least two routes** (different witnesses, different places), so one missed scene is never a dead end.
3. **No clue requires luck.** It requires attention, and spending actions.
4. **You cannot see everything.** 27 actions after the fire; solving the case costs about 17–19. Seeing every scene costs about 45. You must choose.
5. **The village is not a puzzle box. It is people.** Characters act on their own agendas whether or not you are watching.
6. **Lies have fingerprints.** Every false lead can be disproved by a specific, findable fact.
7. **Failure is information, not a dead end.** A wrong accusation ends in a painful scene that shows you exactly which link was wrong (the Reckoning).
8. **The story bends but does not break.** Whichever way you chose in the prologue, the killer had a second way. (See §6, "Wick plans for your kindness and your cruelty.")

---

# 3. Rowan, the protagonist

**Who.** Rowan Ash, 22. Mill helper at Tobin's Mill for three months. Quiet, stubborn, handy with a flour sack, bad at asking for help. Arrived from the north with one bag and a letter of recommendation from "a friend in Harrowmere."

**The wound.** Eleven years ago Harrowmere, Rowan's home village, burned. Rowan's father, Emmet, a journeyman miller, was hanged for it. Rowan, eleven, escaped, and has spent a decade half-believing the story: *my father burned our home.* Taking a job at another mill is Rowan's quiet attempt to be what the family name could not.

**The want (surface).** Clear my name before the twelfth.
**The need (deep).** Learn that scapegoats are made, not found. Rowan's father was one too.

**Voice.** Short sentences. Dry. Kind when nobody is looking.

### Choices at the start of a new game
| Choice | Options | Effect |
|---|---|---|
| **Temperament** | *Kind* / *Sharp* / *Quiet* | Kind: +10 trust with everyone at start, gentle questioning works better. Sharp: you can press a witness harder (but pressure risks them clamming up). Quiet: night actions are 30% less likely to be noticed. No option is strictly best. |
| **Guidance** | *Bold* (no guidance) / *Guided* (the Compass) | See §12. Can be switched at any time. |
| **Name and pronouns** | Player's choice (*she / he / they*) | Cosmetic only; every line is written to work for all three. |
| **Read the Almanac?** | Yes / Later | The Almanac (§13) is always available. |

---

# 4. The clock and the four meters

**Time.** Twelve days. Days 1–3 are the *Prologue* ("the three quiet days"). The mill burns on the night of day 3. Days 4–12 are the investigation. The **Moot** is the evening of day 12.

**Actions.** Three per day. Spend them in daytime or at night; night actions are riskier but reveal things the day hides.

**The four meters.** Everything the player needs to read the situation is on screen.

| Meter | What it means | Goes up when | Danger line |
|---|---|---|---|
| **Suspicion** (the village) | How strongly the village believes you did it | witnesses talk, you flee, you lie, evidence points at you | **70 = arrest.** 100 = the mob takes you at night. |
| **Trust** (per person) | What each villager will risk for you | kindness, kept promises, help, protecting their secrets | Below 20 they will not talk to you. Above 60 they will lie for you. |
| **Danger** (the killer's attention) | How closely the killer watches you | you ask the wrong questions, get too close, use a Second Chance | **60 = the killer arranges an "accident."** |
| **Time** | Days left | always | Day 12 evening. |

Suspicion and Danger pull against each other on purpose: **if the village stops suspecting you (Suspicion falls), the killer starts watching you (Danger rises).** Being safe from the mob is not the same as being safe.

---

# 5. The cast

Fourteen people. The scenario pack may rename or re-cast the seed villagers; the roles are what matter.

| # | Person | Public face | Secret | Wants | Fate |
|---|---|---|---|---|---|
| 1 | **Rowan Ash** (you) | Mill helper, outsider | Father hanged for the Harrowmere fire | To belong | You |
| 2 | **Tobin Marsh**, 58 | Gruff miller, honest, tight-lipped | Keeper of the Founding Deed; found the forgery | To protect the village's land | **Murdered, night 3** |
| 3 | **Old Wick** (Edric Wick), ~70 | The well-keeper. Gentle, funny, remembers every story | *The Quiet Man.* Agent of the Veyne Company; has burned two villages before | Alderbrook's land; and an old revenge on Tobin's family | **The killer** |
| 4 | **Maren Dunn**, 45 | Warm baker; mother to the whole street | Blackmailed by Wick for nine years (her husband's "accident" at the bakehouse was her mistake, and Wick signed the false inquest) | To keep her bakery and her silence | Dies if she speaks without protection |
| 5 | **Ines Taverner**, 38 | Sharp innkeeper and lender | Carries Wick's sealed packets without knowing what's in them; saw a lantern the night of the fire | To stay solvent | **Killed night 7** unless protected |
| 6 | **Giles Hollis**, 16 | Hot-headed lad; mother ill | Lit the grain-shed fire on Wick's quiet suggestion; saw a body | To save his family from eviction | Star witness, or hanged by the village, or silenced |
| 7 | **Elspeth Wren**, 19 | Maren's helper, your friend | Her initials are **E.W.** (a red herring) | To be useful | Ally, or arrested because of you |
| 8 | **Sergeant Pike**, 45 | The Reeve's advance officer. Rigid, fair | Honest. Unaware that his master is bought | Order | Rival; becomes the best ally you can earn |
| 9 | **Reeve Halloran Voss**, 63 | The law, arriving on day 12 | Veyne Company's man; rubber-stamping the land grab | Closure, fast | Final antagonist |
| 10 | **Hesper Brook**, 61 | Village healer, blunt | Can read a body | To be believed | Targeted if she speaks too publicly |
| 11 | **Lily Taverner**, 10 | Ines's niece; sees everything and is not believed | Noticed the well lantern was dark | To be listened to | Protected: **never harmed** |
| 12 | **Aldous Thorn**, 55 | Headman of Thorn Farm; loud | Threatened Tobin over grain prices | A hanging, any hanging | Red herring; mob leader or ally |
| 13 | **Corbin Brand**, ~40 | A drover lodging at the inn since day 1 | Wick's hired hand; the Reeve's coachman in disguise | Money | The ambush; the link to the Reeve |
| 14 | **Corwen**, 25 | Pike's deputy | Honest, nervous | To do right | Shadows you; can be turned |

### The four who matter most (dossiers)

**Old Wick.** The first friend you make. In the original design of this game, *the first thing a player does is give him a loaf of bread.* Here, that loaf is the opening move of the villain's game. He is patient, funny and genuinely warm, and the warmth is real; he is simply not *only* that. He tells stories at the well, hangs his green-glass lantern there every night, and knows everyone's secrets because everyone passes the well. His fingertips are stained dark with walnut ink (he makes it; Maren buys it for labelling flour). *What he does when you aren't looking:* collects secrets, plants rumours through Maren, pays Brand, kills.

**Maren.** She will feed you, hide you, lie to you, and ultimately betray you. She was *told to keep you close "for your own protection."* She believed it. She is the game's heartbreak: the person who loves you most and has helped the killer most.

**Giles.** The boy who will be hanged if you let the village have its way. He is the moral centre of the game. Every accusation of him has to be weighed against the fact that you gave him the coin.

**Sergeant Pike.** If you treat him as an enemy he arrests you on day 9. If you earn his trust he becomes the only person in the valley who can stand in front of the Reeve.

---

# 6. The truth (the case file)

*What really happened. Nothing in this section is ever handed to the player. It is assembled from evidence.*

### The man behind the well
Forty years ago a young clerk named **Edric Wick** was whipped and banished from Alderbrook for theft, on the word of the miller **Tobin's father**. He did not forget. He became **the Quiet Man**: a land-fixer for the **Veyne Company**, which buys villages cheaply by making them fail.

His method never changes:
1. Arrive as something harmless.
2. Gather every secret in the place.
3. Destroy the records that prove who owns what.
4. Burn something. Hang a stranger.
5. Collect.

He has done it twice. **Eskdale**, seven autumns ago. **Harrowmere**, eleven autumns ago. In each village a drifter was hanged for the fire. At Harrowmere it was **Emmet, Rowan's father.** (Villagers remember that Old Wick "visits his sister every autumn." Those were the jobs.)

Alderbrook is his last and best job: his own village, where he has spent twenty-two years becoming the old man everybody trusts. The Veyne canal needs the valley's water. The **Founding Deed**, kept in Tobin's mill, says the commons cannot be sold without the unanimous seal of the Moot. Destroy the Deed, blame a stranger, let the Reeve declare the commons unclaimed, and the Crown sells to the Company. Wick gets a manor and the thing he really wants: **Tobin's family finished, and Alderbrook on its knees.**

### The setup (three months ago)
**Why Rowan, and why it is not a coincidence.** Wick keeps track of the *survivors* of every village he has burned, because he learned something cruel at Eskdale: **a village will convict the child of a hanged arsonist before any evidence is heard.** "Bad blood" does the work for him. He doesn't need to forge a frame; the village's own prejudice is the frame. When the Alderbrook job approached, he looked through his old pages for a survivor of a *mill* fire, someone adrift, unmarried, without a protector. Rowan was working farm to farm in the north. A forged letter of recommendation from "a friend in Harrowmere" reached Tobin; Wick had already told Tobin, over the well wall, that "the lad's a good worker and worse luck than he deserves." Tobin, who liked taking in strays, hired Rowan. **Wick placed Rowan, and then made a friend of him.** The kindest man in the village is the one who knew every sad thing about Rowan before they met.

### The prologue (days 1–3), seen from Wick's side
- **Day 1.** Wick meets Rowan at the well and tells a story. He accepts the loaf (the test: *is this one kind?*). He sends Rowan with a sealed packet to Ines (it is payment for Brand; Ines passes it on). He has already told **Giles** that Tobin's debt ledger, in the mill, will evict the Hollis family at the Reeve's visit. Giles asks Rowan for a coin to buy lamp oil.
- **Day 2.** Wick whispers to Maren that Rowan has been selling flour on the side. Maren mentions it, worried, to Tobin. Tobin, already on edge, blows up at Rowan in the square. Rowan hangs the mill key on the well hook to drink; **Wick pockets it.** That night Tobin confronts Wick at the well-house; Wick agrees to "settle it" at the mill after the bell tomorrow.
- **Day 3.** Tobin, expecting danger, gives Rowan **page 41** of his ledger (a copy of the forged survey with his own note: *"E.W. has sold us. The survey is false. Midnight, the mill, bring the seal."*) and tells Rowan to keep it safe and show no one in Alderbrook. Thorn threatens Tobin loudly in the square over grain prices.

### Night 3: the murder and the fire
- Around eleven, Wick and **Brand** come to the mill. Tobin is struck with the mill's own iron crank. He dies in the office. The strongbox is cut open from outside; the **Founding Deed** is taken. Brand soaks the office and cellar with lamp oil.
- At midnight **Giles**, on Wick's whispered suggestion, sets fire to the *grain shed* (he believes the mill is empty and the ledger will burn). The shed fire spreads. Brand's oil does the rest. The mill is gone in under an hour.
- Wick will say he sat at the well "all night." The village notices the well lantern was dark; Wick has a ready, believable answer: *"The oil ran out. I sat in the dark and thought about Tobin."* This is **a good alibi** and the player must *break it*: Lily confirms the lantern was dark **and** the chandler's ledger shows Wick bought a full can of lamp oil that very afternoon. A man with a full can does not sit in the dark. Maren saw him at her door at midnight, smelling of smoke, asking her to say he'd been at the well.
- Brand's grey horse is stabled at the inn. Under the saddle blanket it carries the **Reeve's brand.**

### The cover-up (days 4–11)
Wick calms the village ("give the boy a fair week"), wins Rowan's trust, and cleans up. Each night he removes whoever knows most and is least protected, and uses the dead as a confession.

### Wick plans for your kindness *and* your cruelty
If you refused Giles the coin on day 1, **Wick gave it to him himself.** If you refused the packet, Ines delivered it. If you skipped the well on day 2, the key was taken from your coat in the bakery. *Whatever you did, his hand was already there.* On the Reckoning screen the player sees both chains: *what you did*, and *what he would have done instead.* It is meant to feel like standing in a room and realising it was built around you.

### The cache (the final shock)
Below the well, in a dry niche only the well-keeper knows, Wick keeps:
- the second copy of the **Founding Deed** (the original sat in the mill; the village's 1612 copy was walled into the well-house by its first keeper, and Wick has hidden it from everyone for twenty-two years);
- every letter from the **Veyne Company**, including those carrying the Reeve's seal;
- a **trophy ledger** of the village's secrets, in walnut ink, with a page for every villager;
- a page titled **"The Stranger"**, dated three months before the player's first day: *"R. Ash. Harrowmere (Emmet, journeyman). Kind. Stubborn. Will not run. Will not be believed."*
- a **trophy shelf**: one small object from the scapegoat of each village he has taken. A carved flour-scoop (**Emmet, Harrowmere**). A drover's belt buckle (**Eskdale**). And **the loaf you gave him on day 1**, wrapped in cloth, with a bite taken out of it and a tag in his hand: *"R. Ash. First gift. Kind."* He has kept the first thing every stranger ever gave him.

---

# 7. The Chain of Seven, and the clue catalogue

A case has seven links, each a question. The **Case Board** in the game shows seven empty slots with their names from day 1, so players always know *what kind* of thing they are missing, without being told the answer.

| # | Link | The question | Truth |
|---|---|---|---|
| 1 | **Motive** | Why would anyone kill Tobin? | The Deed, and the Veyne canal |
| 2 | **Means** | Who had the hand to do it? | Wick: the ink, the seal, Brand |
| 3 | **Meeting** | Who met Tobin that night? | Wick (not you) |
| 4 | **Murder** | How did Tobin die? | Struck dead *before* the fire |
| 5 | **Match** | Who lit the fire? | Two hands: Giles's shed, Brand's oil |
| 6 | **Mask** | Who built the frame? | Wick: the key, the whispers, the false confession |
| 7 | **Master** | Who is behind it all? | The Quiet Man, and the Reeve's seal |

**Evidence strength per link:** 0 *Nothing* · 1 *Heard* (rumour) · 2 *Testimony / Evidence* · 3 *Proof* (two independent sources, or one physical plus one testimony). **A link is "Proven" at strength 3.**

### Clue catalogue
(T = testimony, P = physical, D = document, O = observation. ◆ = red herring.)

| ID | Clue | Where and how | Shows | Link |
|---|---|---|---|---|
| C01 | Wick's walnut-stained fingers | Day 1, talk to Wick at the well; noticeable by anyone who looks | The ink | Mask |
| C02 | The sealed packet's seal | Day 1, carry the packet; peeking shows a bucket-shaped seal | Wick's private seal | Means |
| C03 | The dark well lantern **and** the oil he bought | **Lily (T):** "the well was dark" **plus** the chandler's ledger (D): Wick bought a full can that afternoon. Either alone is explainable; together they break his alibi | Wick's alibi is false | Meeting |
| C04 | The night-2 argument | **Watch the well-house, night 2 (O).** Alternate: Lily saw the two of them arguing | Tobin and Wick quarrelled; "midnight, the mill" | Meeting |
| C05 | **Page 41** | Given by Tobin, day 3. Ambiguous ("E.W.") | The survey is false; a meeting was set | Motive, Means |
| C06 | "Ed." vs "Els." | Tobin's tally book at Ines's inn (he kept receipts there) | Tobin always abbreviated *Edric* as "Ed." and *Elspeth* as "Els.": so E.W. is **Wick** | Means |
| C07 | The stopped watch | Tobin's body / the office (fire night or exhumation) | Stopped at 11:40, glass smashed: *before* midnight | Murder |
| C08 | The wound and the clean lungs | **Hesper (T)** examining the body | Blow to the head; no smoke inhaled | Murder |
| C09 | The strongbox | Ruins, day 4 or fire night | Lock cut from *outside* before the fire; Deed gone | Motive, Murder |
| C10 | The oil | Ruins; Hesper or the chandler | Far more oil than one boy's can: a second hand | Match |
| C11 | Giles's can | Giles (T) | A pint of oil, one shed | Match |
| C12 | **Your key in the ashes** | Pike finds it, day 4 | Frame (you lost it on day 2) | Mask |
| C13 | The pocketed key | **Lily (T):** saw Wick pocket something shiny at the well on day 2 | Wick took your key | Mask |
| C14 | The whisper chain | **Ask Why on the day-2 quarrel** (your own witnessed event); each upstream link is revealed as you collect the testimony of Elspeth → Maren → Wick | The quarrel was *engineered* | Mask |
| C15 | Walnut ink | Maren's flour labels; Wick's fingers; the "confession" | Only two people in Alderbrook use it | Mask |
| C16 | The barred cellar door | Ines's cellar, day 8 | The "suicide" door was barred from *outside* | Mask, Murder |
| C17 | Brand's grey horse | The inn's stable, day 5–9 | Reeve's brand under the saddle blanket | Master |
| C18 | The Reeve's seal | The cache, or Brand's saddlebag | The Reeve is Veyne's man | Master |
| C19 | **Maren's testimony** | Maren (T), needs Trust ≥ 60 and a safe place | Wick at her door at midnight, smelling of smoke | Meeting, Master |
| C20 | **Giles's testimony** | Giles (T), needs Trust ≥ 50 and shelter | "A dry old voice behind the shutter" smelling of walnut | Match, Master |
| C21 | Ines's testimony | Ines (T), **only if alive** | Wick's packets; the lantern | Means, Meeting |
| C22 | **The cache** | Descend the well, day 10–11 | Deed copy, Veyne letters, trophy ledger, "The Stranger" | Motive, Master |
| C23 | The Harrowmere page | The cache | Your father's name in Wick's hand | Master (pattern) |
| C24 | Pike's Eskdale file | Pike (D), needs Trust ≥ 70 | Two villages burned, two drifters hanged, same autumn | Master |
| ◆C25 | Thorn's threat | Public, day 3 | Looks like motive. **Disproved by:** his calving-night alibi (Hesper) | none |
| ◆C26 | Ines's debt ledger | Ines's inn | Tobin owed her 40 crowns. **Disproved by:** she was hosting Brand | none |
| ◆C27 | **E.W.** | Page 41 | Seems to point at Elspeth. **Disproved by C06** | none |

**Redundancy check (each link has two disjoint routes):**
Motive: C09+C22, C05+C22 · Means: C02+C06, C21+C15 · Meeting: C03+C04, C19+C03 · Murder: C07+C08, C09+C16 · Match: C10+C11, C11+C20 · Mask: C13+C14, C15+C16 · Master: C22+C18, C19+C24.

---

# 8. The story, day by day

Each day lists **what always happens** (story beats, stored as data), **the pressure**, and **the decision that costs you.**

## Keeping Wick a surprise (misdirection plan)

A player who has read any mystery will look at the gentle old man at the well and think *it's him.* The design has to make that guess **feel wrong for a long time**, and make the final proof feel like the player's own achievement.

1. **Wick genuinely helps.** Several of his tips are true and useful (he points you to Lily; he warns you about Thorn's mob; he tells you where Giles likes to hide). A villain who only lies is obvious. A villain who is *useful* is a friend.
2. **Wick is a target.** On day 6 a stone is thrown through the well-house window "by someone who wants him quiet," and he wears a bandage for two days. (He did it himself.) The player's instinct is to protect him.
3. **Wick saves Giles once.** On day 6 he talks Thorn's mob out of dragging Giles from the hayloft. It earns him Giles's gratitude and keeps the boy close.
4. **A rotating cast of *real* suspects.** Each has real evidence and a real lie, and each is plausible for about two days:
   - **Thorn** (days 3–5): the public threat, the feud, the mob.
   - **Ines** (days 5–7): the debt, the flush purse, the sighting near the mill.
   - **Pike** (day 5): he appears from nowhere and is *the first to produce your key.* Is he in on it?
   - **Maren** (days 7–9): the walnut ink is on her flour labels, she lied about where she was, and she moved grain out of the mill. **Wick uses walnut ink on purpose, to point at her.**
5. **The ink points at two people.** Maren and Wick. A careless player settles on Maren, the mentor who betrayed them. The reveal that she was being *used* is the second big turn, and the proof that Wick is behind her is the third.
6. **Pike's arrival, the Reeve's coming and Brand's horse are on the table from the start**, so by the time the player learns the Reeve is bought, they have already seen the horse, the seal, and the timing. They just didn't know what they were looking at.

## The Deduction Board (pride, not hand-holding)

The game does not assemble the case for the player. The **Deduction Board** has the seven links as empty slots, and the player **places clues into them by hand** (connecting, for example, *the dark lantern* and *the oil ledger* to *Meeting*).
- **In Bold mode** nothing confirms a placement. The only test is the Moot.
- **In Guided mode** the Compass reports progress per link, never which piece is wrong.
- **The Board never hands out the answer.** It will confirm a link only when the player has placed **a complete, correct pair** for it, in a batch of three placements (like a lock opening when three tumblers are right), so it cannot be brute-forced.
- **When a link locks, the game stops for a beat:** the string pulls tight across the board, a low note sounds, and the village's own ledger line appears: *"Proven."* *This is the moment the player feels clever.*

## THE PROLOGUE: three quiet days
*The prologue teaches the whole game while it plants every seed. It must be good enough that players want to play it twice.*

### Day 1: The Stranger
**Beats.** Tobin pays your wage short ("the mill's running at a loss"). Maren feeds you and asks about home. Elspeth gossips. Old Wick tells you the story of the river that changed its mind.

> *(Day 1. Wick also says, lightly, that "the Moot meets on the commons and always has; that's the one thing in this valley no one owns." It sounds like nostalgia.)*
>
> *"Sit, lad. Everyone who drinks from this well owes it a story. Mine is short. The river once changed its mind about where to run, and everything that mattered in this valley had to move to follow it. A village is only ever the shape of its water."* He smiles. *"You have a kind face. That is a dangerous thing to wear in a place like this."*

**Decisions.**
- Give Wick a loaf? (the first gift; he remembers it)
- Carry his sealed packet to Ines? Peek at it?
- **Giles asks for a coin "for a lamp for my mother."** Give it / give two / refuse. *(This is the coin that becomes the oil.)*
- Tell Maren the truth about Harrowmere, or lie?
**Planted:** C01, C02, the coin, Wick's regard for you, Maren's concern.

### Day 2: A public quarrel
**Beats.** In the square, in front of seven villagers, Tobin accuses you of selling flour on the side. You hang your mill key on the well hook to drink.
**Decision.** Apologise / defend yourself / counter-accuse Tobin of short wages. *(Each is remembered. Apologising lowers Suspicion later but raises Tobin's unease; fighting back makes you look guilty.)*
**Night.** You may **watch the well-house** (C04: you see Tobin and Wick arguing, and hear "midnight, the mill"), visit the inn (you notice a drover with a grey horse), or sleep.
**Planted:** C04, C13, C14, Brand.

### Day 3: The page
**Beats.** Tobin is strange and quiet. Over a bowl of soup he tells you, almost to himself, the oldest law in the valley: *"The commons can't be sold without the seal of the whole Moot. Not the Reeve, not the Crown. Every voice in the valley. That's older than any Reeve."* (**This plants the finale.** The Moot's founding right, and the reason the Deed matters.) At closing he gives you **page 41**: *"Keep this safe. If anything happens to me, show it to no one in Alderbrook."* Aldous Thorn publicly threatens Tobin over grain prices (◆C25). Tobin tells you to stay home that night.
**Decisions.** Read page 41 (the E.W. note) / don't. Tell Elspeth or Maren about it / keep it secret. **Where do you hide it?** (Your room, Maren's oven, the well, on your person.) *Each hiding place is tested later.*
**Night 3.** The bell rings at midnight.

## THE FIRE (set piece, no action cost)

You wake to the bell and the sky. The mill is burning. You have **three moves** before the roof comes down, and the smoke meter is rising. Choose:

| Move | You gain | You risk |
|---|---|---|
| **Force the back door and go for the office** | The stopped watch (C07); the cut strongbox (C09); you see Tobin's body | Smoke damage (−1 action tomorrow); seen coming out of the mill |
| **Drag Tobin's body out** | Hesper can examine it (C08). The body is *evidence* | You are covered in soot and blood. **Suspicion +25.** If you do it alone, villagers swear they saw you *with* the body |
| **Save the grain store** | Trust with Thorn and the farmers | You learn nothing; Tobin burns |
| **Stay back, raise the alarm** | Safe; Suspicion unchanged | You will never know what you could have found |

*If you do none of these and run, Suspicion +15 ("he ran").* If you stay too long, the ceiling falls: **you can die here.** (The game's first real, unforgiving decision.)

## ACT II: THE INVESTIGATION

### Day 4: Ashes
**State.** Suspicion ~35: the quarrel, your key, and a witness who says they saw you running. The village gathers. Tobin is "missing." Thorn demands a rope. **Wick steps forward and calms them:** *"Give the boy a fair week. The Reeve comes on the twelfth. If he is guilty the law will find it."* (Wick buys time because he *needs* the Reeve to arrive.) Pike has not arrived yet.
**Opportunities.** Search the ruins (C09, C10); question Lily (C03, C13); visit Maren; find Giles (missing since the fire).
**Decision.** Where do you spend your first three free actions, with the village still half in shock and half in a mob?

### Day 5: The Sergeant
**Beats.** **Sergeant Pike** arrives. He takes over the inquiry, forbids you to leave, assigns Corwen to shadow you. If you left Tobin's body in the ruins, Pike's men find it in the cellar. **Your key is produced from the ashes (C12).**
**The cruel decision.** Show Pike page 41? If you do, he reads *"E.W."* and **arrests Elspeth.** If you hide it, you are withholding evidence from the law, and he'll know.
**Also.** Brand's horse is in the inn's stable. Whoever looks at the saddle blanket (C17) sees the Reeve's brand, but only a careful eye does.

### Day 6: The boy in the hayloft
**Beats.** You can find **Giles** (he is hiding in a hayloft at Hartley Farm). He is shaking. He confesses to you: *"I lit it. I killed him."* But when you press him: *"He was already dead. He was cold. I saw him through the window. I thought it was a sack."* (**First shock.** Giles started a fire, and didn't kill Tobin.) He says someone told him the ledger was in the mill: *"A dry old voice. Smelled of walnut. Behind the shutter."* (C11, C20.)
**Pressure.** Meanwhile Thorn's mob gathers at the inn to pull Ines in for questioning (◆C26): she was seen near the mill, and Tobin owed her money.
**Decision.** Hide Giles (costs an action every day), turn him in to Pike (earn his trust, and Giles *will be hanged*), or use him as a witness quietly. **Protect Ines from the mob, or follow the Giles lead.** You cannot do both.

### Day 7: The good friend
**Beats.** **Old Wick comes to you.** He is kind, even fatherly: he will speak for your character at the Moot. *He asks whether you've found anything.* (Every answer tells him how much you know. **Danger rises with every honest word.**) That evening Maren asks you to stay at the bakery; she wants to "keep you safe."
**Night 7. Wick's first cleanup** (see §9). Someone dies.

### Day 8 · MIDPOINT: The Confession
**Morning.** The village wakes to news. **A confession has been found, and a body.** Depending on your protection choices it is **Ines** (hanged in her cellar, a note beside her: *"I set the fire for the debt. Forgive me."*), or **Giles** (found drowned, a note in the same hand), or, if you protected them both, **Maren**.
**The village exhales.** Thorn stands down. Pike seems satisfied. **Your Suspicion falls to 10. You are free.**
**This is a false victory.** The note is in **walnut ink** (C15). The cellar door was **barred from outside** (C16). But *everyone is relieved*, and **now every question you ask looks like obsession.**
**The Choice (the midpoint twist).** Wick approaches you warmly and gives you a purse: *"Go north. Start again. The village is ready to forget."* You may **accept and leave.** *(That ends the game here, in the ending **Convenient Peace**. See §11. The Compass will read **Very Cold**.)*
Or stay, and keep digging in a village that wants you to stop.

### Day 9: The baker's confession
**Beats.** If Maren trusts you ≥60, **she breaks:** *"Wick came to my door at midnight. He smelled of smoke. He told me to say he'd been at the well. I have done what he told me for nine years."* (C19.) She is going to repeat it to Pike tomorrow.
**Pike.** If you've been honest with him, he's now working beside you. If not, **he arrests you today** (you lose a day in the cell, but he questions you and the arrest can become the breakthrough).
**The ambush.** If you walk home alone at night, someone shoves you into the millrace. You survive, soaked and bruised, with a clear sense of a **hooded figure on a grey horse.** (Brand. −2 actions tomorrow.)
**Night 9. Wick's second cleanup.** *If Maren has spoken, and isn't protected, she dies.*

### Day 10: The well
You realise the one person who has never been questioned in a village that talks about everything is the man who sits by the water. If your evidence points that way, the **well** itself becomes the question: *what does the keeper know that nobody else does?*
**The descent.** At night, with a rope and a trusted pair of hands at the top (Elspeth, Pike, or Corwen), you climb down the well shaft. This is the game's **thriller set-piece**: the dark, the cold, the echo, the rope creaking. In a dry niche you find the **cache** (C22, C23):
- the Deed;
- the Veyne letters with the **Reeve's seal** (C18);
- the trophy ledger, with a page for every villager;
- the page titled **"The Stranger,"** and, beneath it, the page for **Harrowmere: *Emmet. Hanged.***
- and on a shelf, **your loaf**, with the bite taken out.

**This is the reveal the whole game exists for.** The player realises that *Wick chose them.* That their friendship with Wick was a trap. That their father was innocent. And that their first kindness, the loaf, was filed away as proof they were the right victim.

### Day 11: The old man's offer
**Wick comes to you.** He has known since you came back from the well. He is not angry. He is *delighted.*

> *"Here is the secret of every village I have ever buried, Rowan. Nobody burns a village. A village burns itself, one whisper at a time. I only ever carry the matches. And the stranger. There is always a stranger: someone the whole room can look at while I take the purse."*
> *(He looks at you with something like fondness.)* *"Your father did not say a word at the rope. I admired that. Do try to be louder."*

**Wick's offer.** *Become my heir.* The Company needs a man who can live in a village for twenty years. He will teach you everything. He will make Giles vanish from the story. He will make **your father's name** clean, if you will carry his work on.
**The choices.**
- **Refuse** and walk out, knowing the next night will be hard.
- **Accept** (the ending **Wick's Heir**: the cycle continues; you become the next Quiet Man).
- **Stall**, and set a **trap** with Pike: a witness behind the well-house shutter, a conversation steered to a confession. This works only if you have Pike's trust ≥ 70 and at least five links at strength 2.

**Night 11.** The last cleanup attempt: Brand comes for the evidence and its keepers. **Where you hid everything, and with whom, decides what survives.** The Reeve's herald arrives with a **warrant for summary justice**, hanging on the twelfth at dusk whatever the Moot says.

### Day 12: The Moot
The Reeve arrives at noon. The commons is full. The moot is a four-phase set-piece:

1. **The Accusation.** The Reeve reads the charge: arson and murder, Rowan Ash. Thorn speaks for the village. *You may defend yourself, with whatever you have.*
2. **The Case (an argument, not a menu).** You argue the Chain of Seven against the Reeve *in rounds*. You choose which link to press and which clue to lay on the table. **The Reeve will attack the weakest link first.** *"A stopped watch? Fires stop watches."* You answer with the right second clue (the clean lungs) or the point is lost. Each round the **village reacts** (gasps, a hush, a stranger standing). Strength 3 links land like a hammer; strength 1 links are laughed at. You have a limited number of rounds before the Reeve's patience ends; **choosing which links to press, and in what order, is the skill.**
3. **The Reeve's counter.** He does not want this heard. *"Sit down. The law has been in this valley a great deal longer than your questions."* If the Reeve's seal (C18) is proven, he panics. If not, he dismisses you. **The law itself is the last obstacle.**
4. **The Voice of the Village.** The old law you heard on day 3 matters now: the commons cannot be disposed of without the whole Moot. If the village stands together, **the Moot can overrule the Reeve.** The trust you built decides who stands. Maren (if alive), Pike, Elspeth, Hesper, Giles, even Thorn: each stands, or doesn't.

**Wick's last move.** If cornered, he does not run. He walks to the well. *"A village is only ever the shape of its water."* He drops himself in: or is pulled out and hanged: or is allowed to go free by a Moot that cannot prove enough. **This is decided by the evidence you present.**

---

# 9. The Quiet Man's engine (how the killer acts)

Wick is not scripted. He is a set of **rules stored as data**, evaluated every night by the same rules engine that runs the village. He reacts to *what you did*.

**Each night, Wick:**
1. **Scores every living witness** by `threat = (what they know about him) × (how many people they've told) × (how soon they could speak)`.
2. **Removes protection from the equation.** A witness is *protected* if they are sheltered with someone, guarded by Pike or Corwen, or watched through the night by you or an ally.
3. **Acts on the highest-threat unprotected witness:**
   - **Night 7 and Night 9:** he kills, and leaves a forged "confession" in walnut ink, shaped to close the case and pin it on the dead.
   - **If everyone dangerous is protected:** he turns the village on *you* instead (a planted letter, a witness swearing they saw you, Pike's patience tested).
4. **Raises or lowers his guard against you** according to **Danger**. At **Danger 60** he arranges an "accident" (the millrace).
5. **Adapts.** If a plan is blocked, he uses another lever. Nothing can be blocked forever; the aim is to make every defence *cost* you something.

**The point:** protection takes actions. Actions are scarce. *You will always have to choose who to save.*

**Fair warning built in.** The night before each cleanup the village *feels wrong:* a door left open, a dog that won't stop barking, an NPC who says *"I need to tell you something tomorrow."* If you notice and act, you can save them. If you don't, you will *remember* that you were told.

---

# 10. Deaths and permanent consequences

Death is permanent. Evidence from the dead survives **only if you collected it first.**

| Who | When | Preventable? | What is lost |
|---|---|---|---|
| **Tobin Marsh** | Night 3 | No (before play) | The man who could have named Wick in one sentence |
| **Ines** | Night 7 (default) | Yes: protect her | C21, the packet evidence; her inn's testimony |
| **Giles** | Day 8–9, if the village hangs him on a wrong accusation, or Wick silences him | Yes | C20, the star witness; and the moral weight of a boy you could have saved |
| **Maren** | Night 9, if she speaks unprotected | Yes | C19, the single most devastating testimony |
| **Hesper** | Night 9/11, if she testifies too publicly | Yes | C08, the autopsy |
| **Rowan** | Fire night (smoke), Night 9 (millrace if Danger is high), or the rope on Day 12 | Yes | The game |

**Rules.**
- **No child is ever harmed on screen.** Giles (16) *can* die, but only as the result of the village's decision or Wick's, never as spectacle.
- **Your wrong accusations kill.** If you accuse Giles publicly and the village believes you, he hangs. The game does not let you un-ring that bell (except with a Second Chance).
- **Grief is a mechanic.** When someone you had high Trust with dies, you lose an action the next day ("you can't get out of bed"), and your Compass wobbles.

---

# 11. Endings, rewards and punishments

The Moot's outcome is decided by **the Chain of Seven**, **who stands with you**, and **who is still alive**. Thresholds are on the number of links Proven (strength 3), with the *Murder*, *Match* and *Master* links weighted.

### The nine endings

| Ending | How | What happens |
|---|---|---|
| **THE VILLAGE REMEMBERS** *(true ending)* | ≥6 links Proven, including Murder and Master; the village stands | Wick is taken. The Reeve is arrested by Pike. The Deed is read aloud. **Rowan's father is cleared.** The commons is the village's forever. The Reckoning plays. |
| **THE HARD TRUTH** | 5–6 links, but a key witness died | Wick hangs. The cost is on your conscience: the epilogue names everyone you couldn't save. |
| **ASHES AND LAW** | Wick exposed, but the Reeve's seal unproven | Wick falls, the Reeve walks free to the next village. You are right and powerless; a final shot of Voss's carriage leaving the valley. |
| **MERCY** | You hold the evidence and choose to hide it (to spare Giles, or Maren) | You keep the secret. You live under a lie. Years later Wick's well is still full. |
| **THE WRONG ROPE** | You accuse the wrong person with confidence (Ines, Giles, Elspeth, Thorn) | The village hangs them. The Reckoning shows, link by link, exactly where you went wrong. **This is the worst fate, because it is yours.** |
| **FLIGHT** | You run before the Moot | You live. The village chooses without you. Later, a letter arrives: someone has been hanged in your place. |
| **CONVENIENT PEACE** | You take Wick's purse on Day 8 | You leave. A year on, the canal opens. The Compass would have said *Very Cold.* |
| **WICK'S HEIR** | You accept his offer on Day 11 | The cycle continues. A cold epilogue, narrated in your voice, in a new village, under a new name, kind to a stranger at a well. |
| **THE ROPE** | Suspicion hits 100, or you lose the Moot | You hang. If you collected enough evidence and **Giles or Pike** survives, a **posthumous** epilogue: they reopen the case and clear you, too late. |

### Rewards
- **Allies stand for you** at the Moot; each is a witness with a face and a voice.
- **Pike gives you his badge.** (Special final line.)
- **Rowan's father cleared**, with a special last scene.
- **Perfect run ("No One Left Behind"):** Tobin is the only death.
- **Unaided badge:** completing the game in *Bold* mode.

### The Reckoning (the final screen)
After every ending, the game plays **The Reckoning**: Ask Why on Tobin's death, drawn as a long vertical story, link by link, including the **hidden chain** you never saw. Example:

> **Day 1** — *You gave Giles Hollis a coin.* He bought lamp oil with it.
> **Day 1** — *You gave Old Wick a loaf.* He decided you were kind.
> **Day 2** — *Old Wick whispered to Maren that you were selling flour.* Maren told Tobin. Tobin shouted at you in the square.
> **Day 2** — *You hung your key on the well hook.* Wick put it in his pocket.
> **Day 3** — *Tobin gave you a page.* You hid it where you thought no one would look.
> **Day 3, 11:40 p.m.** — *Tobin Marsh was struck dead in his own mill.* You were asleep.
> **Day 3, midnight** — *Giles lit the shed.* The oil you paid for did the rest.
> **Day 12** — *The village remembers.*
> ***And in a dry niche below the well, a loaf with a bite out of it, and a note that says: "Will do."***

---

# 12. The Compass (optional guidance)

Chosen at the start of a new game. **Can be turned on or off at any moment** from the Almanac or the top bar; the game remembers whether you used it.

| Mode | What you get |
|---|---|
| **BOLD** | No guidance. You get the Case Board (the seven empty slots), the Journal, and the Almanac. Nothing tells you if you are on the right track. Completing in Bold earns the **Unaided** badge. |
| **GUIDED** | The **Compass**: a needle on the top bar that reads **Lost · Cold · Cool · Warm · Hot**, with a **trend arrow** (↑ closer, ↓ farther) since yesterday, and a one-line **reason** after each important decision. |

**What the Compass tells you (and what it never does).**
- ✅ It tells you **how close** your *understanding* is to the truth: *"Warmer. You've learned something about **Means**."*
- ✅ It tells you **when a decision moved you away**: *"Colder. Accusing Elspeth moved you away from the **Meeting**."*
- ✅ It names **a link** (Motive, Means, Meeting, Murder, Match, Mask, Master), never a person.
- ❌ It **never** names the culprit.
- ❌ It **never** says what to do. It says how you're doing.

**How it is computed (all in SQL, no hidden magic).**
```
progress  = Σ strength(link) over the 7 links            (0–21)
misdirect = Σ penalty for each locked-in wrong belief     (public accusation of an innocent: −4;
                                                           destroying/losing key evidence: −3;
                                                           trusting a liar with the case: −2)
score     = progress − misdirect + bonus(protected witnesses alive)
needle    = Lost (<4) · Cold (4–8) · Cool (9–12) · Warm (13–16) · Hot (17+)
trend     = score today − score yesterday
```
A SQL function `case_distance(branch, actor)` computes it from the same evidence table the Moot uses, so the Compass can never disagree with the final judgement. In **Bold** the function is simply never shown.

**Honesty rule.** The Compass reports *understanding*, not outcome. It will say "Hot" even if you are about to lose a witness, because that is a different problem.

---

# 13. The Almanac (the in-game manual)

*"Make him understand everything about the game. Then he can move with confidence."*

A **book icon on the top bar (and the H key)** opens the **Almanac** at any time, even mid-conversation or on the Moot day. It is **spoiler-free**: it explains the rules and the *shape* of a case (the Seven links) but never the answer. Searchable. Written in the same voice as the game.

### Contents
1. **Your case.** Who you are; what you are trying to do; the Moot; what winning looks like.
2. **How a day works.** Morning, daytime, evening, night. Three actions. What each phase offers. What the Evening Bell tells you.
3. **Your actions.** All of them, with cost, risk and typical outcome: *Question, Search, Follow, Watch, Protect, Confront, Hide, Give/Trade/Steal, Rumour, Help, Accuse.* Each with an example.
4. **The four meters.** Suspicion, Trust, Danger, Time. Exactly what moves them.
5. **Witnesses and fog.** *You only know what you saw or were told.* How testimony works. How to read someone's mood. Why a villager lies, and how to catch it.
6. **Clues and evidence.** The four strengths (Heard, Testimony, Evidence, Proof). How two sources make a proof. How to read the Case Board.
7. **The Chain of Seven.** What each link means, with a non-spoiler example from an *unrelated* case.
8. **Ask Why.** How to use the village's memory as a detective tool. Which events you can ask about, and why some trails go cold.
9. **People and protection.** Trust, favours, shelter, and what it costs to keep someone safe.
10. **Time, death and permanence.** What can't be undone.
11. **Second Chance.** Two uses per game. What it undoes. The cost (the village senses it; Danger +15).
12. **The Compass.** What it measures. What it never does. How to switch it.
13. **The Moot.** How the final trial works (phases, evidence, the vote), without spoilers.
14. **Endings (categories only).** That there are many, that none is "game over," and that the Reckoning will explain what happened.
15. **Tips from the village.** "Write down who was where." "Ask the child." "Look at the hands."
16. **FAQ and glossary.**

### Onboarding (so nobody is lost)
1. **The Briefing.** A one-page screen before day 1: who you are, what's coming, and **an invitation to open the Almanac** (never forced).
2. **The Prologue teaches by doing.** Day 1 introduces actions one at a time with a margin note; day 2, witnesses and fog; day 3, evidence and hiding things.
3. **Contextual hints** *("?" buttons).* Every panel has one, jumping to the right Almanac article.
4. **A tutorial recap after the fire.** The game pauses once, so you can check the Case Board and the Almanac before the investigation begins.

---

# 14. Difficulty and fairness

**Hard but achievable.**
- **Action budget.** Days 4–12 give **27 actions**. The cheapest route to Proven on all seven links costs **17–19**. The remaining 8–10 pay for **protection** (≈1 per protected witness per night), travel and recovery from setbacks.
- **Total content costs ≈45 actions.** You *cannot* see everything. That is the design.
- **Two routes per proof** (see §7). One missed scene never closes a door.
- **Hard fail only through your decisions**: Suspicion 100, Danger 60 followed by an ambush, or a catastrophic accusation. Everything else is soft failure with consequences.

**Reward curve.** Early days reward *attention* (each clue is findable by anyone who looks). Middle days reward *judgement* (who to trust, who to protect). Late days reward *courage* (the well, the trap, the Moot).

**The solvability proof.** The project is a DBMS project: so fairness is **tested in SQL**, not asserted:
- A test plays a **par route** through the real `apply_action` and asserts the true ending is reachable.
- A test asserts that **every link has at least two disjoint routes** (distinct witnesses/locations) in the clue table.
- A test asserts that **no single missed scene** removes all routes to any link.
- A test asserts that **the Compass score never decreases when a link's strength increases.**

**Playtest rubric.** A first-time player should *feel stupid for about a day and brilliant for the next.* If they never feel stupid, it's too easy. If they never feel brilliant, it's too hard.

---

# 15. How this maps to the database

The story is **data**, not code. New tables:

| Table | Purpose |
|---|---|
| `scenario` | One row per story (Mystery, Drama, Survival). A new story is a new row and a seed pack. |
| `scenario_role` | Which seed villager plays which role (Wick, Maren, Giles…) |
| `story_beat` | `(scenario, day, phase, condition, effect)`: fixed beats and branching beats, run by the same rules engine as the rest of the village |
| `clue` and `clue_source` | Each clue, where it can be found, which action finds it, and its **link** |
| `case_link` and `evidence` | The Chain of Seven and the strength the *player* holds for each |
| `ending` and `ending_condition` | Declarative endings (thresholds, required survivors) |
| `compass_weight` | The weights behind the Compass |
| `almanac_article` | The manual itself, stored in the database and served by the API |
| `protection` and `wick_agenda` | Who is protected each night; Wick's per-night targeting rule |

**Existing engine concepts the story uses directly:**
- **Event store and hash chain** → nothing can be retconned; the Reckoning is *provable.*
- **Witness rows and RLS** → fog of knowledge = the actual mechanic of testimony.
- **Ask Why (recursive query)** → a *detective tool in play* and the *final reveal.*
- **Scheduled effects** → delayed consequences, cleanups, the Moot clock.
- **Branching / Second Chance** → the rewind power, with its cost.
- **Window functions / materialized views** → the Moot's tally; the leaderboard of "most lives saved".
- **Triggers** → Wick's nightly agenda.

**New DBMS content for the report:** a *state machine* for quests, a *scoring function*, *declarative endings*, *solvability tests*, and a *new experiment*: Wick's targeting query over a witness graph.

---

# 16. Decisions (resolved in review)

| # | Question | Decision |
|---|---|---|
| 1 | Wick as villain, the Reeve as final obstacle | **Keep**, with the misdirection plan above so it is not guessed on day 1 |
| 2 | The personal twist (Rowan's father, Harrowmere, the trophy shelf) | **Keep**, now grounded in village prejudice instead of coincidence |
| 3 | The Day 8 false victory | **Keep** (a deliberate betrayal of the player's relief) |
| 4 | Deaths (Tobin, Ines or Giles or Maren, possibly Hesper, and Rowan) | **Keep.** No child is ever harmed on screen |
| 5 | The Compass | **Keep** as written, plus the Deduction Board |
| 6 | Child-safety rule | **Keep** |
| 7 | The Moot | **More interactive**: an argument in rounds (§8, Day 12) |
| 8 | Rowan's gender | **Player chooses** name and pronouns |

**Next document: the Day-by-Day Production Script**: every line of dialogue, every choice and consequence, and every story beat in the exact form we will load into the database. We write the **Prologue and the Fire** first, so we can build and *play* a vertical slice before writing the rest.
