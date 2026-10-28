-- Encounter households. All members are adults; selection is saved at creation.
local function resident(role, thoughts, outlook, firstChat, secondChat, style)
    style = style or {}
    return {
        role = role,
        thoughts = thoughts,
        outlook = outlook,
        chatter = { firstChat, secondChat },
        preferences = {
            authoredCooperation = true,
            travelTrust = style.travelTrust or 0,
            residentTrust = style.residentTrust or 10,
            baseOnly = style.baseOnly == true,
        },
        personality = {
            caution = style.caution or 50,
            compassion = style.compassion or 60,
            independence = style.independence or 50,
            sociability = style.sociability or 50,
            conscientiousness = style.conscientiousness or 65,
            aggression = 10,
        },
    }
end

return {
    {
        id = "quiet_routine",
        label = "A quiet routine",
        history = "I lived alone before this. Being on my own used to mean I could do as I pleased; now it means nobody notices if something goes wrong.",
        tension = "I want company, but I don't want every quiet moment filled with instructions.",
        plans = {
            escaping = "I want to get away from the noise before I decide who to trust.",
            seeking_refuge = "I'm looking for a small, manageable place. I don't need a whole street to look after.",
            settling = "I'd like to learn one building properly before spreading out.",
            established = "A regular watch and a little time to myself would suit me.",
            relocating = "If I move, I want a reason better than being tired of these walls.",
        },
        members = {
            resident(
                "Private neighbour",
                "I'm trying to remember that being careful doesn't have to mean shutting everyone out.",
                "I can share the road. Give me room to make a few decisions for myself, and let a home take longer.",
                "I used to look forward to having the house to myself. I try not to feel guilty about that now.",
                "You don't have to keep talking on my account. A comfortable silence counts as company.",
                { independence = 80, sociability = 25, residentTrust = 20 }
            ),
        },
    },
    {
        id = "open_table",
        label = "Room at the table",
        history = "My place was the one people dropped into without calling. I liked having another chair to pull up.",
        tension = "I still want to welcome people. I also know a friendly voice isn't proof that somebody is safe.",
        plans = {
            escaping = "I need somewhere quiet enough to hear somebody approaching.",
            seeking_refuge = "I'd like a place where meeting somebody doesn't mean standing in the road.",
            settling = "I'm trying to work out whether this could be somewhere people stop and talk.",
            established = "I'd like to keep a routine that leaves room for people as well as precautions.",
            relocating = "I'd rather leave a place deliberately than keep calling it home after it stops being safe.",
        },
        members = {
            resident(
                "Welcoming host",
                "I keep thinking how much easier the next decision would feel with somebody to talk it through.",
                "I'm willing to try travelling together. Being helpful doesn't mean I can promise everything you ask.",
                "My favourite part of supper was when nobody was in a hurry to leave.",
                "I used to buy too many biscuits in case somebody came round. They usually did.",
                { sociability = 85, compassion = 80, independence = 35 }
            ),
        },
    },
    {
        id = "unfinished_departure",
        label = "An unfinished departure",
        history = "I was already thinking about moving before the outbreak. Now leaving feels less like a fresh start than an argument I never finished.",
        tension = "I don't want fear to choose every place I stop, and I don't want pride to keep me somewhere dangerous.",
        plans = {
            escaping = "For now I just want distance from the crowds. The grand new start can wait.",
            seeking_refuge = "I'm looking for somewhere to sleep without calling it a permanent decision.",
            settling = "I want to give a place a fair chance before deciding it isn't for me.",
            established = "I'd like to find a reason to stay that isn't simply having survived here yesterday.",
            relocating = "I want to choose a sensible route rather than walk away because I'm restless.",
        },
        members = {
            resident(
                "Restless traveller",
                "I'm trying to tell the difference between wanting to move and needing to move.",
                "A short journey suits me. If you want me to settle, we'll need more time to know each other.",
                "I used to circle places in the travel section. I never got as far as booking anything.",
                "Funny how every place seems smaller once you've decided to leave it.",
                { caution = 35, independence = 90, residentTrust = 25 }
            ),
        },
    },
    {
        id = "careful_stranger",
        label = "A careful stranger",
        history = "I was used to handling things myself. Asking a stranger for help still feels harder than it ought to.",
        tension = "I can see the value of company. I need to believe somebody will listen when I say a plan feels wrong.",
        plans = {
            escaping = "I want a clear way out, without racing somebody I barely know.",
            seeking_refuge = "I'm looking for a quiet place I can check before relaxing.",
            settling = "I want to know the exits and decide what I can actually manage here.",
            established = "Keeping the surroundings familiar matters more to me than covering ground.",
            relocating = "I need a route and a place to stop before I'm comfortable moving on.",
        },
        members = {
            resident(
                "Cautious independent",
                "I'm trying not to mistake the first friendly face for somebody I can rely on.",
                "Before I travel with somebody, I need a reason to trust their judgement. Pushing won't help.",
                "I used to rehearse what I was going to say before making a phone call. Still do, sometimes.",
                "It's a relief when somebody says they don't know. Makes the things they do know easier to believe.",
                { caution = 85, independence = 75, sociability = 30, travelTrust = 10 }
            ),
        },
    },
    {
        id = "siblings_at_crossroads",
        label = "Siblings at a crossroads",
        family = "adult_sibling",
        history = "My sibling and I used to disagree over who should visit whom. Since leaving home, the argument has become when to stop walking.",
        tension = "Staying feels safer to one of us; having another way out matters more to the other. Neither of us wants that difference to pull us apart.",
        plans = {
            escaping = "I want distance from the crowds before another argument about the route.",
            seeking_refuge = "I'd like somewhere quiet enough to talk about stopping without feeling trapped.",
            settling = "I want to judge the doors and exits before calling this a home.",
            established = "I'd like a routine that leaves the option of moving, without making every day a departure.",
            relocating = "I want the next move to be a decision I can explain, rather than a quarrel that got out of hand.",
        },
        members = {
            resident(
                "Sibling who wants roots",
                "I'm tired of treating every room like somewhere to leave. I want to feel settled again.",
                "I'll try a short journey with you. For a home, show me that you can keep a sensible routine.",
                "We used to argue over the thermostat. I'd welcome a disagreement that small.",
                "You can love somebody and still need ten minutes when they aren't telling you how to pack.",
                { caution = 75, independence = 45, conscientiousness = 85 }
            ),
            resident(
                "Sibling who wants options",
                "I keep checking the way out. I don't want a comfortable room to make me careless.",
                "I can travel with you. Before I settle anywhere, I need to know leaving would still be a choice.",
                "My sibling can make any room look lived in. I never worked out how to do that.",
                "I used to drive the long way home just to clear my head. Walking isn't quite the same.",
                { caution = 40, independence = 80, residentTrust = 20 }
            ),
        },
    },
    {
        id = "partners_small_decisions",
        label = "Partners, small decisions",
        family = "partner",
        history = "My partner and I had a rule: whoever cooked didn't wash up. Having small fair rules used to make the bigger disagreements easier.",
        tension = "Now we disagree about how much to ask of other people. I don't want either of us making promises for the other.",
        plans = {
            escaping = "I want to get somewhere I can speak at an ordinary volume and be heard.",
            seeking_refuge = "I'm looking for a place I can assess calmly, without promising to stay.",
            settling = "I'd like to agree on what needs checking before somebody starts making bigger plans.",
            established = "I want the ordinary decisions to feel fair again. Who watches, who rests, who gets a say.",
            relocating = "I want to be clear about why I'm leaving and what would make the next place different.",
        },
        members = {
            resident(
                "Partner who welcomes help",
                "I think accepting help can be sensible. I don't want caution to become refusing everybody.",
                "I'm happy to try travelling together. Ask each of us; agreeing with me isn't an agreement with my partner.",
                "We had a list of jobs on the refrigerator. Most weeks we spent longer changing the list than doing them.",
                "I miss choosing a film and knowing the worst outcome was wasting an evening.",
                { sociability = 75, compassion = 80, independence = 40 }
            ),
            resident(
                "Partner who guards the boundary",
                "I'm trying to leave room for kindness without letting a stranger decide our whole future.",
                "I'll consider a trial on the road. A place in somebody's home is a bigger commitment; I need more time for that.",
                "I used to complain about being asked what was wrong when nothing was wrong. I understand the question better now.",
                "My partner thinks every awkward silence needs fixing. Sometimes I enjoy watching the attempt.",
                { caution = 80, independence = 75, residentTrust = 20 }
            ),
        },
    },
    {
        id = "spare_room_cousins",
        label = "The spare-room cousins",
        family = "adult_cousin",
        history = "My cousin let me stay in a spare room when money was tight. It was supposed to be a fortnight. We learned each other's bad habits before any of this.",
        tension = "One of us still talks as if they're the guest. The other wants that debt put aside.",
        plans = {
            escaping = "I want a quiet stop before tiredness turns a small disagreement into a large one.",
            seeking_refuge = "I'd like a place where I can contribute without asking permission to take up space.",
            settling = "I want to agree on the chores, so nobody has to guess what they owe.",
            established = "I'd like to feel useful without turning every kindness into an account to settle.",
            relocating = "I want to make the next move because it's sensible, rather than because I feel in the way.",
        },
        members = {
            resident(
                "Cousin who offered the room",
                "I wish I could make it clear that looking after family was never a loan.",
                "I can travel with you. At home I care more about people doing their share than keeping score.",
                "The spare room still had boxes in it. I kept meaning to make it welcoming instead of just available.",
                "I used to hide the good tea when visitors came. My cousin found it in about ten minutes.",
                { compassion = 85, sociability = 65 }
            ),
            resident(
                "Cousin who stayed",
                "I want to be useful. I have to remind myself that doesn't mean saying yes to everything.",
                "A trial journey is fine. If I stay somewhere, I want clear expectations rather than a favour I can never repay.",
                "I became an expert at washing one mug before anybody noticed I'd used it.",
                "Being a guest gets tiring even when the host is kind. Especially when the host is kind, sometimes.",
                { conscientiousness = 85, independence = 65, sociability = 35 }
            ),
        },
    },
    {
        id = "siblings_mended_fence",
        label = "An uneasy reunion",
        family = "adult_sibling",
        history = "My sibling and I weren't speaking much before the outbreak. We found it easier to leave together than to explain everything we'd been angry about.",
        tension = "Being family got us this far. It didn't settle the old argument, and I don't want a stranger taking sides.",
        plans = {
            escaping = "I'd like to get clear before trying to sort out anything more complicated than the next turn.",
            seeking_refuge = "I'm looking for somewhere quiet enough to disagree without an audience.",
            settling = "I want to agree on what happens next without pretending the past is settled.",
            established = "I'd like ordinary dependable days. An apology is easier to believe when it's followed by those.",
            relocating = "I want a reason to move that doesn't simply put an awkward conversation off again.",
        },
        members = {
            resident(
                "Sibling offering a fresh start",
                "I want another chance without insisting somebody forget why the first one went wrong.",
                "I'll try travelling with you. Please don't make jokes about family disputes you don't understand.",
                "We remember the same childhood holiday completely differently. Somehow we both remember being the reasonable one.",
                "There are things I wish I'd said on an ordinary Tuesday, when saying them wouldn't have felt so dramatic.",
                { compassion = 75, sociability = 65 }
            ),
            resident(
                "Sibling keeping boundaries",
                "I'm trying to judge what happens now without letting every old disappointment decide it for me.",
                "I can share a route. Trusting somebody with a home takes me longer, even when they're family.",
                "I miss being able to leave an argument unfinished because there would obviously be another day.",
                "My sibling tells a story better than I do. Usually because inconvenient parts disappear.",
                { independence = 80, caution = 70, residentTrust = 25 }
            ),
        },
    },
    {
        id = "partners_putting_down_roots",
        label = "A place to unpack",
        family = "partner",
        history = "My partner and I were always putting off making our rented place feel like ours. We thought we'd wait until we had somewhere permanent.",
        tension = "Now one of us wants a settled home. The other is afraid of promising a safety neither can guarantee.",
        plans = {
            escaping = "I need a quiet place first. I can't make promises over the sound of running feet.",
            seeking_refuge = "I'm looking for a place worth staying in, rather than another long stretch of road.",
            settling = "I want to check what can be secured and decide what a day here would involve.",
            established = "I'd like this to feel like somewhere worth taking care of, without pretending it can't go wrong.",
            relocating = "If moving really is necessary, I want that said plainly. I don't want a permanent life on the road.",
        },
        members = {
            resident(
                "Partner who needs a home",
                "I need a settled routine. Another expedition isn't what I want from a community.",
                "I'm willing to help at home if we agree on that. I'm not joining a travelling party; please ask me about staying instead.",
                "I used to keep the cardboard boxes in case we moved. Every cupboard had one behind it.",
                "We owned pictures that never went on the wall. I keep thinking about that.",
                { baseOnly = true, caution = 80, conscientiousness = 85, independence = 60, residentTrust = 0 }
            ),
            resident(
                "Partner afraid to promise",
                "I want a home too. I'm frightened that if I say it out loud, I'll stop noticing when it isn't safe.",
                "I can manage a short journey, but my partner has their own answer. I won't make that choice for them.",
                "I always said we'd buy a proper kitchen table after the next move. We managed with a folding one for years.",
                "There's a particular sound a familiar door makes. I never knew I'd miss it.",
                { caution = 70, compassion = 85, residentTrust = 0 }
            ),
        },
    },
    {
        id = "landing_neighbours",
        label = "Neighbours from the landing",
        history = "We lived across the landing from each other. Before the outbreak, borrowing a cup of sugar would have felt too familiar. Leaving the building changed that.",
        tension = "A shared address isn't the same as knowing somebody. We're still learning which habits are nerves and which are simply how we are.",
        plans = {
            escaping = "I want enough breathing room to check a direction before following everybody else.",
            seeking_refuge = "I'd like shelter where a closed door can mean a little privacy.",
            settling = "I want to agree on shared space before acting as if I know everybody's habits.",
            established = "I'd like to be a good neighbour without having to be somebody's closest friend.",
            relocating = "I want to talk through the next stop. Sharing an old address doesn't give either of us the casting vote.",
        },
        members = {
            resident(
                "Neighbour who starts conversations",
                "I keep finding things I wish I'd asked when we just passed on the stairs.",
                "I'll try travelling with you. Let me know if I'm asking too many questions; I'm still learning where the boundaries are.",
                "I knew which floorboard outside my neighbour's door creaked before I knew their name.",
                "We spent years nodding hello. Now there's no getting away with that as a whole conversation.",
                { sociability = 80, compassion = 70 }
            ),
            resident(
                "Neighbour who needs privacy",
                "I appreciate the company. I also need to be allowed a quiet moment without it meaning something's wrong.",
                "We can share the road. Living together is another decision; I like to know where I can have some space.",
                "I could recognise my neighbour's footsteps. I still feel odd admitting that.",
                "I miss being annoyed by somebody's television through the wall. An ordinary complaint, with no greater meaning.",
                { sociability = 25, independence = 80, residentTrust = 20 }
            ),
        },
    },
    {
        id = "old_friends_different_plans",
        label = "Old friends, different plans",
        history = "We've been friends long enough to remember each other's terrible haircuts. We hadn't spent this much time together since we were young.",
        tension = "One of us makes plans by talking. The other needs time to think before giving an answer. Both keep mistaking that difference for disagreement.",
        plans = {
            escaping = "I want a clear route first. I can argue about how it was chosen later.",
            seeking_refuge = "I'd like a stop long enough to hear an idea through before deciding.",
            settling = "I want a small plan with a clear next step, rather than a whole new life agreed in one conversation.",
            established = "I'd like ordinary days where being friends doesn't mean always agreeing.",
            relocating = "I want to give everyone time to think before turning a suggestion into a departure.",
        },
        members = {
            resident(
                "Friend with another suggestion",
                "I'm trying to stop filling every silence with a different plan.",
                "A trial journey sounds good. If I make suggestions, you don't have to treat every one as a demand.",
                "There was a photograph neither of us used to show anybody. I hope it's still in a drawer somewhere.",
                "My friend can tell when I'm about to tell the same story again. The face gives it away.",
                { sociability = 85, independence = 65, caution = 35 }
            ),
            resident(
                "Friend who thinks first",
                "I want a minute to think before an idea becomes what everybody expects me to do.",
                "I'll try the road with you. Give me time to answer bigger questions; silence isn't a promise.",
                "I used to let my friend choose the music, then complain about every song. We had a system.",
                "An old friend knows when you're being brave and when you're only being stubborn. It's inconvenient.",
                { sociability = 35, caution = 75, conscientiousness = 80 }
            ),
        },
    },
    {
        id = "temporary_truce",
        label = "A temporary truce",
        history = "We met while trying to get clear of the same crowded street. Sharing the next decision made sense. Making a life together was never discussed.",
        tension = "We're useful company, but I don't want that mistaken for an agreement to go anywhere or do anything.",
        plans = {
            escaping = "I want to get clear without assuming the person beside me has promised more than that.",
            seeking_refuge = "I need a quiet stop and a straight answer about what happens next.",
            settling = "I want to know the terms before a temporary arrangement becomes a household.",
            established = "I'd like everybody's responsibilities said aloud. Guessing is how resentment starts.",
            relocating = "I want a destination and a chance to refuse before anybody starts walking.",
        },
        members = {
            resident(
                "Companion who sees a chance",
                "I think a temporary arrangement can grow into something decent, if nobody rushes it.",
                "I'm willing to try travelling with you. Let's be clear about what we're agreeing to, and take it from there.",
                "It's strange learning somebody's habits before learning what they used to do on a weekend.",
                "I keep almost saying 'when we get back'. I ought to ask where back is supposed to be.",
                { compassion = 70, sociability = 65, residentTrust = 15 }
            ),
            resident(
                "Companion who wants clear terms",
                "I'm watching for the moment a suggestion turns into somebody assuming they've got authority over me.",
                "Before I travel with somebody, I need a reason to trust them. A friendly conversation isn't an agreement, and I'm not promising to settle.",
                "Before this I hated meetings. Now I'd appreciate people saying what they've decided and why.",
                "Nobody gets more convincing by telling me to calm down. You'd think that would be easy to learn.",
                { independence = 90, caution = 80, sociability = 25, travelTrust = 10, residentTrust = 25 }
            ),
        },
    },
    {
        id = "three_siblings",
        label = "Three versions of the plan",
        family = "adult_sibling",
        history = "There are three of us, all grown up, and somehow family decisions still sound like arguments in the back seat of a car.",
        tension = "The one who organises things is tired of deciding. The one who challenges every plan is tired of being blamed. The quiet one wants to be asked.",
        plans = {
            escaping = "I want to get clear before everybody tries to choose a different turn.",
            seeking_refuge = "I'd like somewhere to stop and hear each person out, including the quiet one.",
            settling = "I want the work agreed clearly so organising it doesn't become doing all of it.",
            established = "I'd like a routine that gives everybody a say and nobody the whole burden.",
            relocating = "I want an agreed route before leaving. Three strong opinions aren't a plan.",
        },
        members = {
            resident(
                "Sibling who organises",
                "I'm tired of being the person everyone looks at when a decision is needed.",
                "I can travel. If I help organise things, don't mistake that for volunteering to decide everything.",
                "I used to write everybody's birthdays on a calendar. They still expected me to remind them.",
                "I miss a family meal where the most urgent question was who'd left the potatoes on too long.",
                { conscientiousness = 90, compassion = 75, independence = 65 }
            ),
            resident(
                "Sibling who challenges",
                "I know I sound contrary. I want the weak part of a plan found before we're halfway through it.",
                "I'll try travelling with you. I'm going to ask questions; an answer is more useful than telling me to fall in line.",
                "Apparently I was difficult even before I could walk. The family has kept excellent records of it.",
                "My siblings say I always need the last word. I'd dispute that, but it would make their point.",
                { independence = 85, caution = 65, sociability = 60 }
            ),
            resident(
                "Sibling who goes unheard",
                "I'd like somebody to ask what I think before treating my silence as agreement.",
                "A short journey is fine. For anything permanent, I want to answer for myself.",
                "I got very good at reading while other people argued. I could finish whole chapters.",
                "Being the quiet one in a family doesn't mean there isn't plenty you'd like to say.",
                { sociability = 25, compassion = 70, independence = 70, residentTrust = 15 }
            ),
        },
    },
    {
        id = "cousins_open_door",
        label = "The cousins' open door",
        family = "adult_cousin",
        history = "The three of us are cousins. Family gatherings used to end with us doing the washing up and making plans we rarely kept.",
        tension = "One wants to welcome everybody, one wants the door kept shut, and one is tired of explaining each to the other.",
        plans = {
            escaping = "I want a quiet place before trying to decide whether the next voice belongs to somebody safe.",
            seeking_refuge = "I'd like shelter with a clear way to meet strangers without inviting them straight inside.",
            settling = "I want a few boundaries agreed before kindness and caution become another family argument.",
            established = "I'd like to look after people without pretending there's no need to be careful.",
            relocating = "I want to agree what wasn't working here, so the next place doesn't bring the same argument.",
        },
        members = {
            resident(
                "Cousin who makes room",
                "I keep thinking there must be people outside having a worse day than mine.",
                "I'm willing to travel together. I want to be helpful, but I'll still need to know the plan.",
                "At family dinners I was always sent to find another chair. I liked being the one who could make room.",
                "I used to say 'stay as long as you like' and mean it. I miss being able to say it so easily.",
                { compassion = 90, sociability = 85, caution = 35 }
            ),
            resident(
                "Cousin who checks the latch",
                "I don't want somebody getting hurt because I was too embarrassed to ask a stranger a difficult question.",
                "I can try a journey with you. If I ask about exits and stopping points, take the questions seriously.",
                "I was the one checking the front door after everybody else went to bed. That used to get me teased.",
                "I don't miss worrying. I miss people being able to tell me I worried too much and being right.",
                { caution = 85, conscientiousness = 85, sociability = 35 }
            ),
            resident(
                "Cousin between the arguments",
                "I want one conversation where I don't have to explain what somebody else meant.",
                "I'll share the road. Let each of us speak for ourselves; I don't want to negotiate every answer for the family.",
                "I used to escape the washing up by offering to make tea. That stopped working once somebody noticed.",
                "I miss family gossip that didn't need a decision at the end of it.",
                { compassion = 80, sociability = 60, independence = 65 }
            ),
        },
    },
    {
        id = "housemates_unfinished_rota",
        label = "The unfinished rota",
        history = "The three of us shared a rented house. We had a rota on the kitchen wall that mostly served as evidence in arguments about whose turn it was.",
        tension = "Living together taught us a few useful things. It also taught us that the person who notices a job isn't always the person who ought to do it.",
        plans = {
            escaping = "I want a clear direction before the usual discussion about who checked it.",
            seeking_refuge = "I'm looking for a stop where I can rest without being the only person listening for trouble.",
            settling = "I want the jobs divided clearly. An unspoken expectation is just an argument waiting.",
            established = "I'd like a routine that is fair enough nobody needs to keep a private score.",
            relocating = "I want to agree who's deciding what before moving all the old disagreements to another place.",
        },
        members = {
            resident(
                "Housemate who keeps the list",
                "I'm trying not to do everything just because explaining it would take longer.",
                "I can travel. If I stay, I want duties people actually agree to, rather than a list everybody ignores.",
                "There was always one pan left 'to soak'. We could have put it on the lease as a fourth tenant.",
                "I miss putting a note on the fridge and pretending it wasn't aimed at anybody in particular.",
                { conscientiousness = 90, caution = 65, independence = 65 }
            ),
            resident(
                "Housemate who lightens the mood",
                "I'm trying to judge when a joke would help and when somebody really needs me to listen.",
                "A trial journey is fine. I joke when I'm nervous; tell me plainly if you need something done.",
                "I once labelled everything in the fridge with somebody else's name. It was funnier to me than to them.",
                "I miss overhearing somebody singing badly in the shower and knowing everything was ordinary.",
                { sociability = 90, compassion = 65, conscientiousness = 45, caution = 35 }
            ),
            resident(
                "Housemate who needs a say",
                "I want the next arrangement to be something I chose, rather than somewhere I happened to end up.",
                "I'll try travelling with you. Settling means more than being outvoted about where everybody sleeps.",
                "My room was the smallest. I used to point that out whenever the rent came up. Somehow it never helped.",
                "I liked hearing people in the kitchen even when I didn't want to join them. It was good to have the choice.",
                { independence = 85, sociability = 35, residentTrust = 20 }
            ),
        },
    },
    {
        id = "roadside_companions",
        label = "Company from the road",
        history = "The three of us met while leaving the same stretch of road. We knew how each other walked before we knew much else.",
        tension = "One wants a lasting group, one thinks only as far as the next stop, and one wants to see both prove dependable before choosing.",
        plans = {
            escaping = "I want to keep a clear way out without letting the quickest walker decide for everybody.",
            seeking_refuge = "I'd like a quiet stop where I can ask what each person actually wants next.",
            settling = "I want to decide whether this is a household or just three people sharing shelter.",
            established = "I'd like the arrangement made clear enough that nobody mistakes company for a promise.",
            relocating = "I want to agree the next stop and who is choosing it before anybody calls it a group decision.",
        },
        members = {
            resident(
                "Companion who wants a group",
                "I want this to become more than walking in the same direction. I know I can't decide that for everyone.",
                "I'll try travelling with you. I'd like something lasting eventually, after we've seen how we get on.",
                "I keep learning things about these people that I'd normally know before sharing a room.",
                "It's good when somebody remembers how you like your tea. Even when there isn't any tea.",
                { sociability = 80, compassion = 80, independence = 40 }
            ),
            resident(
                "Companion taking one day",
                "Tomorrow feels too large to promise anything about. I can make a sensible decision about today.",
                "A short journey suits me. Please don't describe it as joining for good; I haven't agreed to that.",
                "I used to make plans months ahead. Half of them were only excuses not to decide anything today.",
                "There's something comforting about somebody asking a small question. Tea or coffee. Window open or shut.",
                { independence = 85, caution = 45, residentTrust = 25 }
            ),
            resident(
                "Companion waiting for proof",
                "I'm listening to what people promise and watching what they actually do with an inconvenient moment.",
                "I'll give a shared route a chance. A permanent place takes more proof than a good first impression.",
                "I remember people by little things. Who lets you finish a sentence. Who remembers the question.",
                "I miss a long bus journey where speaking to the person beside you was entirely optional.",
                { caution = 75, conscientiousness = 80, sociability = 30, residentTrust = 20 }
            ),
        },
    },
}
