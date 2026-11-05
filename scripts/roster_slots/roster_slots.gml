/// @desc The fights of the bosses whose stages aren't built yet, as slot
///       tables (`slot_functions`), so each can be practised from its locked
///       card on the rack (X) and written one slot at a time.
///
/// Every slot here is a placeholder (`slot_n`, `slot_s`), and so is every
/// boss's def: its title, its hue, Ziggy's sprite and Mika's cut-in. To
/// write a slot, replace its row with the attack's own (see
/// `slot_functions` for the row's fields). A boss whose stage gets built
/// moves its def and table into the stage's own script.
///
/// The counts are the owner's tiers: Ziggy five non-spells and five spells;
/// Sylvia, Kara, Vin'Zhen, Ashiah and Sapphire eight and ten; Florentius ten
/// and twelve; Kremlatiel ten and thirteen; everyone else seven and eight.
/// Non-spells and spells alternate, and the spells left over come last.

// ---------------------------------------------------------------------------
// Demon Ruins (Ziggy is in `stage_ziggy`)
// ---------------------------------------------------------------------------

function athena_def() {
    return slot_boss_def("ATHENA", "the spider assassin", BCOL_VIOLET);
}

function athena_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

/// @desc Sylvia's N1 and N2 and his iris drafts wait on the drafting table
///       (`draft_sylvia`).
function sylvia_def() {
    return slot_boss_def("SYLVIA", "the egregore", BCOL_MAGENTA);
}

function sylvia_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_s(9),
        slot_s(10),
    ];
}

function florentius_def() {
    return slot_boss_def("FLORENTIUS", "the demon king", BCOL_ROSE);
}

function florentius_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_n(9), slot_s(9),
        slot_n(10), slot_s(10),
        slot_s(11),
        slot_s(12),
    ];
}

// ---------------------------------------------------------------------------
// Yokai Zone
// ---------------------------------------------------------------------------

function oscura_def() {
    return slot_boss_def("OSCURA", "the hakutaku", BCOL_CYAN);
}

function oscura_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

/// @desc The duo fight, as one boss for now.
function mikoto_rena_def() {
    return slot_boss_def("MIKOTO AND RENA", "the kitsune and the nogitsune",
                         BCOL_EMBER);
}

function mikoto_rena_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function ayana_def() {
    return slot_boss_def("AYANA", "the moon rabbit", BCOL_INDIGO);
}

function ayana_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function kara_def() {
    return slot_boss_def("KARA", "the daitengu", BCOL_AMBER);
}

function kara_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_s(9),
        slot_s(10),
    ];
}

// ---------------------------------------------------------------------------
// Eternal Forest
// ---------------------------------------------------------------------------

function haveri_def() {
    return slot_boss_def("HAVERI", "the alchemist", BCOL_AZURE);
}

function haveri_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function astyr_def() {
    return slot_boss_def("ASTYR", "the forest ranger", BCOL_SPRING);
}

function astyr_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function faol_def() {
    return slot_boss_def("FAOL", "the urisk of the lake", BCOL_JADE);
}

function faol_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function vinzhen_def() {
    return slot_boss_def("VIN'ZHEN", "the God of Life", BCOL_LIME);
}

function vinzhen_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_s(9),
        slot_s(10),
    ];
}

// ---------------------------------------------------------------------------
// Land of the Dead (Velka is in `stage_grove`, Mika in `stage_sanctum`)
// ---------------------------------------------------------------------------

function corvus_def() {
    return slot_boss_def("CORVUS", "the crow revenant", BCOL_INDIGO);
}

function corvus_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function ashiah_def() {
    return slot_boss_def("ASHIAH", "the Living God of Death", BCOL_CRIMSON);
}

function ashiah_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_s(9),
        slot_s(10),
    ];
}

// ---------------------------------------------------------------------------
// Crystal Caverns
// ---------------------------------------------------------------------------

function zeek_def() {
    return slot_boss_def("ZEEK", "the technician", BCOL_CYAN);
}

function zeek_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function sally_def() {
    return slot_boss_def("SALLY", "the salamander-kobold", BCOL_EMBER);
}

function sally_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function zalerus_def() {
    return slot_boss_def("ZALERUS", "the gold-plated dragon", BCOL_GOLD);
}

function zalerus_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_s(8),
    ];
}

function sapphire_def() {
    return slot_boss_def("SAPPHIRE", "the carbuncle", BCOL_AZURE);
}

function sapphire_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_s(9),
        slot_s(10),
    ];
}

// ---------------------------------------------------------------------------
// The secret boss
// ---------------------------------------------------------------------------

function kremlatiel_def() {
    return slot_boss_def("KREMLATIEL", "the seraphic wyvern", BCOL_GOLD);
}

function kremlatiel_slots() {
    return [
        slot_n(1), slot_s(1),
        slot_n(2), slot_s(2),
        slot_n(3), slot_s(3),
        slot_n(4), slot_s(4),
        slot_n(5), slot_s(5),
        slot_n(6), slot_s(6),
        slot_n(7), slot_s(7),
        slot_n(8), slot_s(8),
        slot_n(9), slot_s(9),
        slot_n(10), slot_s(10),
        slot_s(11),
        slot_s(12),
        slot_s(13),
    ];
}
