/// @desc What Szuix and Mika say before they fight (`talk_functions`).
///
/// PLACEHOLDER: every line here was written to show the conversation
/// working, not to be kept. The lines are set in ASCII (see `talk_functions`).

function mika_talk_lines() {
    return [
        talk_say(TalkWho.Player,
                 "Shelves to the sky and not one guard worth the name. "
                 + "Whoever keeps this place is very sure of himself."),
        talk_say(TalkWho.Boss,
                 "You are tracking sand across a floor older than your "
                 + "whole bloodline, little imp."),
        talk_say(TalkWho.Player,
                 "There it is. I was starting to think the rings ran "
                 + "themselves."),
        talk_card(),
        talk_say(TalkWho.Boss,
                 "Every memory in this archive was bequeathed to my lord. "
                 + "You have come to take what was freely given."),
        talk_say(TalkWho.Player,
                 "I've come for yours. The rest is just on the way."),
        talk_say(TalkWho.Boss,
                 "Then stand still. I will file you under 'brief'."),
    ];
}
