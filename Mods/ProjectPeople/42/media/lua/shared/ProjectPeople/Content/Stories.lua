-- Former lives and outbreak accounts. These memories grant no skills or items.
local Stories = {
    plans = {
        escaping = "I'm trying to get clear of the crowds. I'll think about tomorrow once there's somewhere quiet to stop.",
        seeking_refuge = "I'm looking for a place with sound doors and more than one way out. It doesn't have to be much.",
        settling = "I'd like to stay put for a while. First I need to work out whether this place is safe enough.",
        established = "I'm trying to keep a routine. Make a few plans, check the surroundings, get through the day.",
        relocating = "I'm thinking about moving on. I'd rather choose the time than wait until I have to run.",
    },
    familyPlans = {
        escaping = "We're trying to get clear of the crowds. I want us somewhere we can hear each other without shouting.",
        seeking_refuge = "We're looking for somewhere defensible. A place to rest would make the next decision easier.",
        settling = "We're deciding whether we can stay around here. Somewhere that feels like home would be good.",
        established = "We're trying to keep a routine and look out for each other. Having someone to answer to helps.",
        relocating = "We're talking about moving somewhere safer. I want us to agree on the route before we leave.",
    },
    absentRelative = "I lost contact with the others when we got separated. I don't know where they are now.",
    separatedFamily = "Some of the family got separated from us. I don't know where they are now.",
    separatedCompanions = "Some of the people I was travelling with got separated from me. I don't know where they are now.",
    backgrounds = {
        outbreakFamily = "We left when our neighbourhood stopped feeling safe. There wasn't time for a proper goodbye.",
        outbreakSolo = "I thought I'd only be away from home for a little while. I didn't even clear the dishes.",
        aftermath = "I've moved between temporary shelters since the outbreak. None felt like somewhere I could stay.",
        longTerm = "I've been getting by for months. I miss having a day that doesn't need so much planning.",
    },
    -- Each detail belongs to its former life; unrelated fragments are never mixed.
    lives = {
        {
            before = "I worked the counter at a diner. Breakfast was always the busiest part of the day.",
            details = {
                "I used to know the regulars by their orders before I knew their names.",
                "On my days off I'd still wake up in time for the opening shift.",
            },
        },
        {
            before = "I was a mechanic at a small garage. Mostly tired cars that had to last another year.",
            details = {
                "I liked getting an old engine to turn over. That first steady idle was worth the aggravation.",
                "I'd listen to ball games on the radio while I swept up after closing.",
            },
        },
        {
            before = "I stocked shelves at a grocery store. I could walk every aisle in my sleep.",
            details = {
                "I used to complain about the music they played. Now I can barely remember the songs.",
                "The best part of a late shift was the quiet walk home.",
            },
        },
        {
            before = "I sorted mail before dawn and delivered it when we were short of drivers.",
            details = {
                "You learn which porches have a loose step. People don't always think to warn you.",
                "I liked seeing the same streets wake up every morning.",
            },
        },
        {
            before = "I worked in a public library, mostly returns and the front desk.",
            details = {
                "I always had a stack of books I meant to read. I never seemed to make it smaller.",
                "I liked finding a book for somebody who could only remember the colour of the cover.",
            },
        },
        {
            before = "I drove a school bus. There were stretches of that route I knew better than my own street.",
            details = {
                "I used to take my lunch at the depot and enjoy ten minutes without anybody calling my name.",
                "I still slow down in my head when I think about those narrow bends.",
            },
        },
        {
            before = "I cleaned rooms at a roadside motel. People left in a hurry even before all this.",
            details = {
                "There was always one room with the television too loud and another that wanted extra towels.",
                "At home I grew flowers in coffee cans. There wasn't much space, but they did all right.",
            },
        },
        {
            before = "I did maintenance in an apartment building. Leaks, bad locks, lights that wouldn't stay on.",
            details = {
                "I liked the small jobs you could finish before lunch. Something fixed, somebody pleased.",
                "I spent my own weekends putting off repairs at home. It seemed fair at the time.",
            },
        },
        {
            before = "I worked a packing line at a warehouse. The shifts were long and the breaks were short.",
            details = {
                "I played cards on my lunch break. Nobody ever agreed on the rules.",
                "I used to count the days until payday, then wonder where the money went.",
            },
        },
        {
            before = "I worked at a hardware store. Half the job was figuring out what people meant to ask for.",
            details = {
                "Some customers brought the broken part. Others brought a drawing on the back of an envelope.",
                "I liked the gardening section best. It smelled better than the paint counter.",
            },
        },
        {
            before = "I cut hair in a little shop. We heard most of the local news before the paper did.",
            details = {
                "I had regulars who wanted the same cut every time and still brought a photograph.",
                "I used to turn the radio up when I swept the floor after closing.",
            },
        },
        {
            before = "I kept the books for a small business. Receipts in shoeboxes, late bills, the usual.",
            details = {
                "I liked a crossword with my coffee. In ink, which was usually a mistake.",
                "People thought I liked numbers. Mostly I liked being able to put something in order.",
            },
        },
        {
            before = "I worked at a laundromat. There was always a machine rattling or somebody short of change.",
            details = {
                "I read old magazines between customers. The same few pages, over and over.",
                "I could tell which dryer was about to quit just by the sound it made.",
            },
        },
        {
            before = "I worked on a farm outside town. Fences, feed, whatever needed doing before dark.",
            details = {
                "I used to envy people who could sleep late on Sundays. Animals don't know it's Sunday.",
                "I liked the kitchen garden more than the field work. You could see the difference a day made.",
            },
        },
        {
            before = "I worked in a bakery. Most mornings I was on my feet before the streetlights went off.",
            details = {
                "I got so used to the smell of bread that I barely noticed it. I'd give a lot to smell it now.",
                "I liked making the plain loaves best. Nothing fancy, just getting them right.",
            },
        },
        {
            before = "I delivered furniture. Stairs, narrow doors, people swearing they'd measured the room.",
            details = {
                "I used to draw on my lunch bags when we were waiting for somebody to come home.",
                "I liked the empty truck on the drive back. It meant the hard part was done.",
            },
        },
        {
            before = "I painted houses. Most of the work was preparation that nobody noticed afterwards.",
            details = {
                "I could never pick a colour for my own place. Every room stayed the same shade of cream.",
                "I spent my free evenings fishing when the weather held. I didn't mind coming back empty-handed.",
            },
        },
        {
            before = "I pumped gas and worked the register at a service station.",
            details = {
                "People asked me for directions all day. Some already had the map open the wrong way round.",
                "I saved the road maps we stopped selling. I liked looking at places I'd never been.",
            },
        },
        {
            before = "I worked in a factory sewing seat covers. Same machine, same noise, every shift.",
            details = {
                "At home I'd mend clothes while the television was on. It was hard to sit with nothing to do.",
                "I grew tomatoes in buckets by the back steps. They never looked like the picture on the packet.",
            },
        },
        {
            before = "I was a nursing assistant. Long shifts, sore feet, and never quite enough time.",
            details = {
                "I liked the quiet part of a night shift when somebody finally managed to sleep.",
                "On days off I took long walks. It helped leave work at work.",
            },
        },
        {
            before = "I repaired televisions and radios in a little shop. People kept things going as long as they could.",
            details = {
                "I liked the stubborn sets best, once they were fixed. Before that I had other names for them.",
                "I used to tape songs off the radio and try to cut out the announcer's voice.",
            },
        },
        {
            before = "I took tickets and cleaned up at a movie theatre. I knew the endings of films I'd never sat through.",
            details = {
                "I always meant to stay after my shift and watch something properly. Usually I just went home.",
                "I liked hearing everybody argue about the film on the way out.",
            },
        },
        {
            before = "I was a custodian at a school. Most of my work started when everybody else went home.",
            details = {
                "There was a particular quiet to the building at night. I used to like that.",
                "I listened to cassette tapes while I worked. I knew exactly where each one would start to drag.",
            },
        },
        {
            before = "I did roofing when the work was there and odd jobs when it wasn't.",
            details = {
                "I used to spend wet mornings at the kitchen table, hoping the weather would clear.",
                "I liked going bowling after payday. I was never as good as I thought I was.",
            },
        },
        {
            before = "I worked in a restaurant kitchen. Mostly prep and washing up, whatever we were behind on.",
            details = {
                "I used to get home too tired to cook and eat a sandwich standing at the sink.",
                "I liked the hour before opening, when everything was ready and nothing had gone wrong yet.",
            },
        },
        {
            before = "I drove a truck on short delivery runs. Same towns, different loading docks.",
            details = {
                "I had a favourite breakfast stop on every route. That was how I remembered the miles.",
                "I used to keep a little notebook of fuel costs. I liked knowing where every dollar went.",
            },
        },
        {
            before = "I taught adults who were studying for their high school equivalency exams.",
            details = {
                "I liked seeing somebody solve a problem they'd decided was beyond them.",
                "I spent Sunday afternoons marking work at the kitchen table. I always meant to finish earlier.",
            },
        },
        {
            before = "I took photographs for a small newspaper. Store openings, ball games, things like that.",
            details = {
                "I liked the photographs where nobody had noticed the camera yet.",
                "I spent more time waiting for people to stand still than I ever did taking pictures.",
            },
        },
        {
            before = "I was between jobs. I'd been doing yard work and helping people move to cover the rent.",
            details = {
                "I had a list of places to call about work. It felt like everything depended on getting one answer.",
                "I used to sit on the porch in the evening and work out what I could afford until Friday.",
            },
        },
        {
            before = "I was taking evening classes while I worked part-time at a store.",
            details = {
                "I did my reading on the bus. Usually the same paragraph three times.",
                "I was saving up for a better car. Every time I got close, the old one needed something.",
            },
        },
        {
            before = "I'd retired from the county road crew. I was still getting used to having my mornings free.",
            details = {
                "I started keeping a vegetable patch. It turned out I could find plenty of work for myself.",
                "I used to walk to the store for a newspaper even when I didn't need anything else.",
            },
        },
        {
            before = "I stayed home and kept the household running. There was always something else to do.",
            details = {
                "I sewed curtains, stretched the grocery money, and never got around to sorting the spare room.",
                "I liked having people over for supper. Nothing special, just enough chairs round the table.",
            },
        },
    },
    incidents = {
        outbreak = {
            solo = {
                "When the roads backed up, I left the car and walked. I thought I'd be able to come back for it.",
                "I waited for someone to say it was safe to go outside. In the end I had to make that decision myself.",
                "I was away from home when things turned bad. I couldn't get through on the phone, and I couldn't get back.",
                "I left after a night of shouting in the street. In the morning I couldn't face opening the front door again.",
                "I followed other people out of town until the road got too crowded. After that I took a different way.",
                "The radio kept giving advice that didn't match what I could see outside. I stopped waiting for it to make sense.",
            },
            family = {
                "We agreed to leave when the shouting reached our street. None of us wanted to be the first to say it.",
                "We tried the main road with everyone else. Once it stopped moving, we decided to go on foot.",
                "We waited too long for news that somebody had things under control. Eventually we made our own decision to leave.",
                "We left before daylight, arguing about which way to go. Being outside together settled that argument for a while.",
                "We thought we'd only need somewhere to stay for one night. That was easier to say than leaving for good.",
                "We couldn't get a clear answer on the telephone. We decided to leave rather than spend another night waiting beside it.",
            },
        },
        aftermath = {
            solo = {
                "At first I kept circling back towards home. After a few weeks I stopped pretending that was a plan.",
                "I've stayed in a few places since then. I leave when the noise outside starts getting closer.",
                "I used to follow any voice I heard. I've had to learn to wait and listen first.",
                "For a while I counted every day. Somewhere along the way I lost count and decided not to start again.",
                "The hardest part was giving up the idea of somebody coming to tell me what to do next.",
                "I tried staying on the move all the time. After a while I was too tired to make sensible decisions.",
            },
            family = {
                "We've tried a few places since leaving home. It's hard to rest when everyone thinks the next noise is at the door.",
                "We disagree about where to go, but we agreed that rushing into another place wouldn't help.",
                "For the first few weeks we kept talking about going home. We talk about somewhere safe now.",
                "We've learned to discuss the route before setting off. It's a poor time for an argument once you're outside.",
                "At first we tried to travel as far as we could each day. We had to learn that being exhausted isn't progress.",
                "We used to wait for news every evening. Now we spend that time talking through what we can do ourselves.",
            },
        },
        long_term = {
            solo = {
                "I've had months to get used to this, but some mornings I still expect an ordinary day.",
                "I've stopped thinking of shelter as somewhere I can keep forever. It makes leaving a little easier.",
                "I know I need other people. It's getting past that first conversation that's difficult.",
                "I used to measure a good day by how far I got. Now a quiet day counts for plenty.",
                "After this long, I miss having something small to look forward to. A film on television. A day off.",
                "I've made plans and changed them more times than I can count. I try to leave room for being wrong.",
            },
            family = {
                "After months of this, we can tell when someone needs a quiet minute. We weren't always that considerate.",
                "We still talk about the things we argued over before. Somehow those arguments seem almost comforting now.",
                "We've learned that looking after each other includes saying when a plan is a bad idea.",
                "We try to talk about something besides surviving. Some evenings that takes a real effort.",
                "We've changed our plans so many times. We try to make the next decision together instead of defending the last one.",
                "We used to say we'd start living again when things settled down. We can't keep putting every ordinary thing off.",
            },
        },
    },
}

local function pick(lines, value)
    return lines[math.floor(value * #lines) + 1]
end

function Stories.background(era, family, selection)
    if not selection then
        return era == "outbreak" and (family and Stories.backgrounds.outbreakFamily or Stories.backgrounds.outbreakSolo)
            or era == "aftermath" and Stories.backgrounds.aftermath
            or Stories.backgrounds.longTerm
    end
    local life = pick(Stories.lives, selection.life)
    local accounts = Stories.incidents[era] or Stories.incidents.long_term
    local text = life.before
        .. " "
        .. pick(life.details, selection.detail)
        .. " "
        .. pick(accounts[family and "family" or "solo"], selection.incident)
    if family and selection.absent then
        text = text .. " " .. Stories.absentRelative
    elseif family and selection.separated then
        text = text .. " " .. (selection.companions and Stories.separatedCompanions or Stories.separatedFamily)
    end
    return text
end

function Stories.plan(stage, family)
    return (family and Stories.familyPlans or Stories.plans)[stage]
end

return Stories
