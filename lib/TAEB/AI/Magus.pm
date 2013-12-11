package TAEB::AI::Magus;
use Moose;
use TAEB::OO;
use TAEB::Util qw/uniq all any sum refaddr first/;
extends 'TAEB::AI';

use TAEB::AI::Magus::GoalManager;
use TAEB::AI::Magus::QueueManager;

has goal_manager => (
    is      => 'ro',
    isa     => 'TAEB::AI::Magus::GoalManager',
    default => sub { TAEB::AI::Magus::GoalManager->new },
);

has queue_manager => (
    is      => 'ro',
    isa     => 'TAEB::AI::Magus::QueueManager',
    default => sub { TAEB::AI::Magus::QueueManager->new(magus => shift) },
);

has last_wish => (
    is      => 'rw',
    isa     => 'Str',
    clearer => '_clear_last_wish',
);

with (
    'TAEB::AI::Role::Action::Backoff' => {
        action       => 'TAEB::Action::Cast',
        label        => 'sleep',
        max_exponent => 3,
        filter       => sub {
            my ($self, $action) = @_;
            return $action->spell->name eq 'sleep';
        },
        # just blackout for a few turns
        blackout_when => sub { 1 },
        clear_when => sub { 1 },
    },
);

our @behaviors = (qw/
    pray

    put_on_conflict
    take_off_conflict
    heal_self
    multi_bolt
    cast_sleep
    drop_scare_monster
    melee
    single_bolt
    put_on_regen
    put_on_invis
    put_on_tc
    wait_scare_monster
    hunt

    wish
    recharge_wishing
    wrest_wish

    pickup_goody

    pickup_food
    to_food
    eat_inventory
    eat_tile_food

    uncurse_goody

    identify_.*
    real_identify

    wear_.*
    buff_.*
    put_on_pois_res

    take_off_regen
    take_off_invis

    to_unknown_items
    to_goody

    blank_crap

    sacrifice_here
    shed_carcass
    to_altar
    pickup_sac
    to_sac

    open_door
    to_door

    oracle_statues

    practice_spells

    wait_blind
    explore

    descend
    to_stairs

    hang_around_altar

    magic_map
    search
/);

our @METHODS;

sub next_action {
    my $self = shift;

    my $queued = $self->queue_manager->next_queued_action;
    if ($queued) {
        $self->currently($self->queue_manager->currently);
        return $queued;
    }

    for my $behavior (@behaviors) {
        for my $method (grep { /^$behavior$/ } @METHODS) {
            my $action = $self->$method
                or next;

            $self->currently($method);

            if (ref($action) eq 'ARRAY') {
                $self->queue_manager->enqueue_actions(@$action);
                $self->queue_manager->currently($method);
                return $self->queue_manager->next_queued_action;
            }

            return $action;
        }
    }

    $self->currently('to_search');
    return $self->to_search;
}

sub put_on_regen {
    # regen speeds up hunger, and we're clearly starting to get desperate,
    # so don't compound the situation
    return if TAEB->nutrition < 100;

    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of regeneration");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of regeneration',
        is_cursed => 0,
    ) or return;

    return unless TAEB->current_level->has_enemies
               || TAEB->in_pray_heal_range;

    return TAEB::Action::Wear->new(item => $ring);
}

sub put_on_invis {
    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of invisibility");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of invisibility',
        is_cursed => 0,
    ) or return;

    return unless TAEB->current_level->has_enemies;

    return TAEB::Action::Wear->new(item => $ring);
}

sub put_on_tc {
    return unless TAEB->senses->is_teleporting;
    return if TAEB->senses->has_teleport_control;

    # XXX ideally TAEB would know this
    return if TAEB->inventory->find("Master Key of Thievery");

    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of teleport control");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of teleport control',
        is_cursed => 0,
    ) or return;

    return TAEB::Action::Wear->new(item => $ring);
}

sub put_on_pois_res {
    return if TAEB->senses->poison_resistant;
    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of poison resistance");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of poison resistance',
        is_cursed => 0,
    ) or return;

    return TAEB::Action::Wear->new(item => $ring);
}

sub drop_scare_monster {
    return; # XXX drop doesn't work well yet :(

    return if TAEB->hp > TAEB->maxhp / 3;
    return if TAEB->current_tile->find_item("scroll of scare monster");
    return if !TAEB->current_level->has_enemies;

    my $scroll = TAEB->inventory->find("scroll of scare monster")
        or return;

    return TAEB::Action::Drop->new(
        items => [$scroll],
    );
}

sub wait_scare_monster {
    return unless TAEB->current_tile->find_item("scroll of scare monster");

    if (TAEB->hp == TAEB->maxhp) {
        return; # XXX pickup doesn't work :(
    }

    # wait til HP is back up
    return TAEB::Action::Search->new;
}

sub take_off_regen {
    # no sense in taking off regen if we're not fully healed up!
    return if TAEB->hp < TAEB->maxhp;

    my $ring = TAEB->equipment->is_wearing_ring("ring of regeneration")
        or return;

    return if TAEB->current_level->has_enemies;

    return TAEB::Action::Remove->new(item => $ring);
}

sub take_off_invis {
    my $ring = TAEB->equipment->is_wearing_ring("ring of invisibility")
        or return;

    return if TAEB->current_level->has_enemies;

    return TAEB::Action::Remove->new(item => $ring);
}

sub put_on_conflict {
    # conflict speeds up hunger, and we're clearly starting to get desperate,
    # so don't compound the situation
    return if TAEB->nutrition < 100;

    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of conflict");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of conflict',
        is_cursed => 0,
    ) or return;

    # no way jose
    return if has_adjacent_friendly();

    # only bother with conflict if there are multiple enemies
    return unless TAEB->current_level->has_enemies > 1;

    return TAEB::Action::Wear->new(item => $ring);
}

sub take_off_conflict {
    my $ring = TAEB->equipment->is_wearing_ring("ring of conflict")
        or return;

    # oh f*%$!! bail!
    return TAEB::Action::Remove->new(item => $ring)
        if has_adjacent_friendly();

    # no time to take off dis ring
    return if has_adjacent_enemy();

    # there's still work to do...
    return if TAEB->current_level->has_enemies > 1;

    return TAEB::Action::Remove->new(item => $ring);
}

sub buff_wield_magicbane {
    my $magicbane = TAEB->inventory->find("Magicbane")
        or return;
    return if $magicbane->is_wielded;

    return TAEB::Action::Wield->new(weapon => $magicbane);
}

sub buff_write_scroll {
    my $marker = TAEB->inventory->find(
        identity => "magic marker",
        charges  => [ undef, sub { $_ > 0 } ],
    ) or return;

    my $scroll = first { defined } (
        TAEB->inventory->find("scroll of blank paper", is_blessed => 1),
        TAEB->inventory->find("scroll of blank paper", is_uncursed => 1),
        TAEB->inventory->find("scroll of blank paper", is_cursed => 0),
    );
    return unless $scroll;

    return TAEB::Action::Write->new(
        marker   => $marker,
        identity => 'identify',
        onto     => $scroll,
    );
}

sub buff_conserve_oil {
    my $lit_oil = TAEB->inventory->find(type => "potion", is_lit => 1)
        or return;

    return TAEB::Action::Apply->new(item => $lit_oil);
}

sub buff_polypotion_spellbook {
    my $self = shift;

    my $polymorph = TAEB->inventory->find("potion of polymorph")
        or return;

    # prefer blessed books since you're guaranteed to learn them
    my @books = uniq (
        TAEB->inventory->find(type => 'spellbook', is_blessed => 1),
        TAEB->inventory->find(type => 'spellbook', is_cursed => 0),
    );

    for my $book (@books) {
        next unless $self->spellbook_is_useless($book);

        return TAEB::Action::Dip->new(
            item => $book,
            into => $polymorph,
        );
    }

    return;
}

sub spellbook_is_useless {
    my $self = shift;
    my $book = shift;

    my $identity = $book->identity;

    # unidentified spellbooks are always useless
    return 0 if !$identity;

    return 1 if $identity eq "spellbook of blank paper";

    # spellbooks from which we've already learned are effectively useless
    my $spell_name = $book->spell;
    return 1 if TAEB->spells->find($spell_name);

    return 0;
}

sub buff_polypile_spellbook {
    my $polymorph = TAEB->inventory->find(
        identity => "wand of polymorph",
        charges  => [ undef, sub { $_ > 0 } ],
    ) or return;

    # can't polypile if we're standing on items
    return if TAEB->current_tile->items;

    # prefer blessed books since you're guaranteed to learn them
    my @all_books = uniq (
        TAEB->inventory->find(type => 'spellbook', is_blessed => 1),
        TAEB->inventory->find(type => 'spellbook', is_cursed => 0),
    );

    my @selected_books;

    for my $book (@all_books) {
        my $identity = $book->identity;

        # don't polymorph unidentified spellbooks
        next unless $identity;

        # don't polymorph spellbooks we haven't learned yet
        unless ($identity eq "spellbook of blank paper") {
            my $spell_name = $book->spell;
            next unless TAEB->spells->find($spell_name);
        }

        push @selected_books, $book;
    }

    return unless @selected_books;

    my $all_blessed  = all { $_->is_blessed } @selected_books;
    my $all_uncursed = all { $_->is_uncursed } @selected_books;

    return [
        TAEB::Action::Drop->new(
            items => \@selected_books,
        ),

        TAEB::Action::Zap->new(
            wand      => $polymorph,
            direction => '>',
        ),

        sub {
            my ($self, $name, $event) = @_;
            return unless $name eq 'got_item';

            my $item = $event->item;

            if (@selected_books == 1) {
                $item->did_polymorph_from($selected_books[0]);
            }
            else {
                $item->did_polymorph;

                $item->is_cursed(0);
                $item->is_blessed(1) if $all_blessed;
                $item->is_uncursed(1) if $all_uncursed;
            }
        },

        TAEB::Action::Pickup->new,
    ];
}

sub buff_1_read_new_spellbook {
    my @books = TAEB->inventory->find(
        type      => 'spellbook',
        is_cursed => 0,
    );

    for my $book (@books) {
        if ($book->identity) {
            next if $book->identity eq "spellbook of blank paper";

            my $spell_name = $book->spell;
            next if TAEB->spells->find($spell_name);
        }

        next if $book->difficult_for_level >= TAEB->level
             && $book->difficult_for_int >= TAEB->int;

        return TAEB::Action::Read->new(
            item => $book,
        );
    }
    return;
}

sub can_enchant_weapon {
    my $weapon = TAEB->equipment->weapon or return 0;

    return 0 if ($weapon->numeric_enchantment||0) > 5;

    return 1;
}

sub buff_enchant_weapon {
    my $self = shift;

    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of enchant weapon',
        is_cursed => 0,
    ) or return;

    return unless $self->can_enchant_weapon;

    return dip_bless($scroll) || TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub buff_enchant_armor {
    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of enchant armor',
        is_cursed => 0,
    ) or return;

    for my $slot (TAEB->equipment->armor_slots) {
        my $equip = TAEB->equipment->$slot
            or next;
        return if !$equip->enchantment_known;
        return if $equip->numeric_enchantment >= 4;
    }

    return dip_bless($scroll) || TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub buff_see_invis {
    my $potion = TAEB->inventory->find(
        identity => 'potion of see invisible',
        is_cursed => 0,
    ) or return;

    return dip_bless($potion)
        unless $potion->is_blessed;

    return TAEB::Action::Quaff->new(
        from => $potion,
    );
}

sub buff_great_potion {
    my $potion = TAEB->inventory->find(
        identity => [
            'potion of gain ability',
            'potion of gain energy',
        ],
        is_cursed => 0,
    ) or return;

    return dip_bless($potion) || TAEB::Action::Quaff->new(
        from => $potion,
    );
}

sub buff_slow_digestion {
    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;
    return if TAEB->equipment->is_wearing_ring("ring of slow digestion");

    my $ring = TAEB->inventory->find(
        identity  => 'ring of slow digestion',
        is_cursed => 0,
    ) or return;

    return TAEB::Action::Wear->new(item => $ring);
}

sub buff_enchant_ring {
    return if TAEB->equipment->left_ring
           && TAEB->equipment->right_ring;

    my @rings = TAEB->inventory->find(type => 'ring', is_cursed => 0);
    for my $ring (@rings) {
        next if $ring->is_worn;
        next unless $ring->enchantment_known;
        next unless $ring->numeric_enchantment >= 2;

        return TAEB::Action::Wear->new(item => $ring);
    }

    return;
}

sub buff_haste_self {
    return if TAEB->senses->is_very_fast;

    my $spell = TAEB->find_castable("haste self")
        or return;

    # if we're at max power, we can cast it even if it's very likely to fail
    return unless TAEB->power == TAEB->maxpower
               || $spell->fail <= 30;

    return TAEB::Action::Cast->new(spell => $spell);
}

sub buff_speed_monster {
    return if TAEB->senses->is_fast;

    my $wand = TAEB->inventory->find(
        identity => "wand of speed monster",
        charges  => [ undef, sub { $_ > 0 } ],
    ) or return;

    return TAEB::Action::Zap->new(
        wand      => $wand,
        direction => '.',
    );
}

sub buff_genocide {
    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of genocide',
        is_cursed => 0,
    ) or return;

    return dip_bless($scroll) || TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub buff_make_eventual_corpses {
    my $self = shift;

    return unless TAEB->hp == TAEB->maxhp
               && TAEB->power > TAEB->maxpower / 3;
    return if TAEB->current_level->has_enemies;

    my $spell = TAEB->find_castable("create monster");
    if ($spell && $spell->fail < 50) {
        my $regen = $self->put_on_regen;
        return $regen if $regen;

        return TAEB::Action::Cast->new(
            spell => $spell,
        );
    }

    return unless TAEB->nutrition < 500
               || $self->on_sacable_altar;

    my $wand = TAEB->inventory->find(
        identity => 'wand of create monster',
        charges  => [ undef, sub { $_ > 0 } ],
    );
    if ($wand) {
        my $regen = $self->put_on_regen;
        return $regen if $regen;

        return TAEB::Action::Zap->new(
            wand => $wand,
        );
    }

    my $scroll = TAEB->inventory->find(
        identity => 'scroll of create monster',
    );
    if ($scroll) {
        my $regen = $self->put_on_regen;
        return $regen if $regen;

        return TAEB::Action::Read->new(
            item => $scroll,
        );
    }

    return;
}

sub buff_drop_crap {
    my $self = shift;
    my @crap;

    my $magicbane = TAEB->inventory->find('Magicbane');

    push @crap, TAEB->inventory->find(identity => 'quarterstaff')
        if $magicbane;

    push @crap, TAEB->inventory->find(identity => 'bell', is_artifact => 0);

    if (@crap) {
        return TAEB::Action::Drop->new(items => \@crap);
    }

    return;
}

sub blank_crap {
    my $self = shift;
    return unless TAEB->level >= 5;

    return if TAEB->current_level->is_minetown;
    return unless TAEB->current_level->has_type('fountain');

    my @crap = TAEB->inventory->find(
        identity => [
            'scroll of light',
            'scroll of confuse monster',
            'scroll of destroy armor',
            'scroll of fire',
            'scroll of food detection',
            'scroll of gold detection',
            'scroll of amnesia',
            'scroll of earth',
            'scroll of punishment',
            'scroll of stinking cloud',

            'potion of booze',
            'potion of fruit juice',
            'potion of see invisible',
            'potion of sickness',
            'potion of confusion',
            'potion of hallucination',
            'potion of restore ability',
            'potion of sleeping',
            'potion of blindness',
            'potion of invisibility',
            'potion of monster detection',
            'potion of object detection',
            'potion of levitation',
            'potion of speed',
            'potion of acid',
            'potion of oil',
            'potion of paralysis',
        ],
    );

    if (TAEB->has_item("magic marker")) {
        push @crap, grep { $self->spellbook_is_useless($_) }
                    grep { ($_->identity||"") ne "spellbook of blank paper" }
                    TAEB->inventory->find(type => "spellbook");
    }

    return unless @crap;

    if (TAEB->current_tile->type eq 'fountain') {
        return TAEB::Action::Dip->new(
            item => $crap[0],
            into => 'fountain',
        );
    }

    path_to('fountain');
}

sub on_sacable_altar {
    my $tile = TAEB->current_tile;

    return unless $tile->type eq 'altar';

    return if $tile->in_temple && !$tile->is_coaligned;

    return 1;
}

sub identify_engrave_wand {
    return unless TAEB::Action::Engrave->is_advisable;

    for my $wand (TAEB->inventory->find(type => 'wand', identity => undef)) {
        next unless $wand->tracker->engrave_useful;

        if (TAEB->current_tile->engraving eq '') {
            return TAEB::Action::Engrave->new(engraver => '-');
        }

        return TAEB::Action::Engrave->new(engraver => $wand);
    }
}

sub identify_oil_potion {
    for my $potion (TAEB->inventory->find(type => 'potion', identity => undef)) {
        next if $potion->total_cost;

        next unless $potion->tracker->includes_possibility('potion of oil');

        return TAEB::Action::Apply->new(item => $potion);
    }
}

sub real_identify {
    my $self = shift;

    my $spell = TAEB->spells->find("identify");

    # if we know ID but can't cast it right now, go ahead and wait til we can
    # again
    return if $spell && !$spell->castable;

    my $scroll;
    if (!$spell) {
        $scroll = TAEB->inventory->find(
            identity => 'scroll of identify',
        ) or return;
    }

    # do I have interesting items to ID?
    my @items;
    for my $item (TAEB->inventory_items) {
        if ($self->would_identify($item)) {
            push @items, $item;
        }
    }

    return if !@items;

    return TAEB::Action::Cast->new(
        spell => $spell,
    ) if $spell;

    return if @items < 3;

    return dip_bless($scroll) || TAEB::Action::Read->new(
        item => $scroll,
    );
}

my %is_cool_type = (
    amulet    => 1,
    ring      => 1,
    scroll    => 1,
    spellbook => 1,
    potion    => 1,

    wand      => 0, # wands can be ID'd by engraving
);

sub would_identify {
    my $self = shift;
    my $item = shift;

    return 0 if defined($item->identity);

    return 1 if $is_cool_type{$item->type};

    return;
}

sub _wear_type {
    my $self = shift;
    my %args = @_;

    my $subtype = $args{subtype};
    my $ideal = $args{ideal};
    my @blockers = @{ $args{blockers} || [] };

    return if TAEB->equipment->$subtype
           && TAEB->equipment->$subtype->is_cursed;

    my @possibilities = TAEB->inventory->find(
        subtype   => $subtype,
        is_cursed => 0,
    ) or return;

    # first, any matches for ideal? (speed boots, helm of brilliance, etc)
    my $best;
    if ($ideal) {
        for my $candidate (@possibilities) {
            $best = $candidate if $candidate->identity||'' eq $ideal;
        }
    }

    # failing that, unknown enchantment
    if (!$best) {
        for my $candidate (@possibilities) {
            $best = $candidate if !$candidate->enchantment_known;
        }
    }

    # failing that, best AC
    if (!$best) {
        $best = shift @possibilities;
        for my $candidate (@possibilities) {
            $best = $candidate if $candidate->ac > $best->ac;
        }
    }

    return unless $best;
    return if $best->is_worn;

    my @steps;
    for my $blocker (@blockers, $subtype) {
        if (TAEB->equipment->$blocker) {
            push @steps, TAEB::Action::Remove->new(
                item => TAEB->equipment->$blocker,
            );
        }
    }

    push @steps, TAEB::Action::Wear->new(
        item => $best,
    );

    return \@steps;
}

sub wear_boots {
    my $self = shift;
    $self->_wear_type(
        subtype => 'boots',
        ideal   => 'speed boots',
    );
}

sub wear_helmet {
    my $self = shift;
    $self->_wear_type(
        subtype => 'helmet',
        ideal   => 'helm of brilliance',
    );
}

sub wear_gloves {
    my $self = shift;
    $self->_wear_type(
        subtype => 'gloves',
        ideal   => 'gauntlets of dexterity',
    );
}

sub wear_1_shirt {
    my $self = shift;
    $self->_wear_type(
        subtype  => 'shirt',
        blockers => ['cloak', 'bodyarmor'],
    );
}

sub wear_2_bodyarmor {
    my $self = shift;
    $self->_wear_type(
        subtype  => 'bodyarmor',
        ideal    => 'silver dragon scale mail',
        blockers => ['cloak'],
    );
}

sub wear_3_cloak {
    my $self = shift;
    $self->_wear_type(
        subtype => 'cloak',
        ideal   => 'cloak of magic resistance',
    );
}

sub pray {
    return unless TAEB::Action::Pray->is_advisable;

    if (TAEB->in_pray_heal_range) {
        # don't pray if we're relatively safe and we have a ring of regeneration
        return if !TAEB->current_level->has_enemies
            && TAEB->inventory->find(
                    identity  => 'ring of regeneration',
                    is_cursed => 0,
                );
    }
    elsif (TAEB->nutrition < 0) {
        # always a good idea
    }
    else {
        return;
    }

    if (TAEB->current_tile->type eq 'altar') {
        my @water;
        push @water, TAEB->inventory->find(
            identity   => 'potion of water',
            is_uncursed => 1,
        );
        push @water, TAEB->inventory->find(
            identity   => 'potion of water',
            buc      => undef,
        );
        return TAEB::Action::Drop->new(
            items => \@water,
        ) if @water;
    }

    return TAEB::Action::Pray->new;
}

sub wish {
    my $wand = TAEB->inventory->find(
        identity => "wand of wishing",
        charges  => [ undef, sub { $_ > 0 } ],
    ) or return;

    return TAEB::Action::Zap->new(
        wand => $wand,
    );
}

sub wrest_wish {
    my $wand = TAEB->inventory->find(
        identity        => "wand of wishing",
        charges         => 0,
        recharges       => [undef, 1],
        times_recharged => 1,
    ) or return;

    # save the wrest for MKoT, when we can handle its damage
    return if !TAEB->seen_artifact('Master Key of Thievery')
           && TAEB->hp <= 25;

    return TAEB::Action::Zap->new(
        wand => $wand,
    );
}

sub recharge_wishing {
    my $wand = TAEB->inventory->find(
        identity        => "wand of wishing",
        charges         => 0,
        recharges       => [ undef, 0 ],
        times_recharged => 0,
    ) or return;

    my $blessed_scroll = TAEB->inventory->find(
        identity   => "scroll of charging",
        is_blessed => 1,
    );

    if ($blessed_scroll) {
        return TAEB::Action::Read->new(
            item   => $blessed_scroll,
            charge => $wand,
        );
    }


    my $uncursed_scroll = TAEB->inventory->find(
        identity => "scroll of charging",
        is_uncursed => 1,
    );

    my $dip = $uncursed_scroll && dip_bless($uncursed_scroll);
    return $dip if $dip;


    my $unknown_scroll = TAEB->inventory->find(
        identity => "scroll of charging",
        buc      => undef,
    );

    $dip = $unknown_scroll && dip_bless($unknown_scroll);
    return $dip if $dip;


    my $cursed_scroll = TAEB->inventory->find(
        identity => "scroll of charging",
        is_cursed => 1,
    );

    $dip = $cursed_scroll && dip_bless($cursed_scroll);
    return $dip if $dip;

    return;
}

sub heal_self {
    return unless TAEB->hp * 2 < TAEB->maxhp;

    my $spell = TAEB->find_castable("extra healing") || TAEB->find_castable("healing");
    if ($spell) {
        return TAEB::Action::Cast->new(
            spell     => $spell,
            direction => '.',
        );
    }

    return unless TAEB->hp * 3 < TAEB->maxhp;

    my $potion = TAEB->inventory->find(
        identity => [
            "potion of healing",
            "potion of extra healing",
            "potion of full healing",
        ],
    ) or return;

    return TAEB::Action::Quaff->new(
        from => $potion,
    );
}

sub multi_bolt {
    return unless TAEB->current_level->has_enemies;

    my $spell = attack_spell()
        or return;
    my $is_force_bolt = $spell->name eq 'force bolt';

    my $verboten = 0;
    my $seen_enemies;
    my $direction = TAEB->current_level->radiate(
        sub {
            my ($tile, $distance) = @_;
            if ($tile->has_enemy && $tile->monster->currently_seen) {
                $seen_enemies++;

                # XXX verboten needs to forbid directions
                if ($distance == 1 && $tile->monster->has_possibility('gas spore')) {
                    $verboten = 1;
                    return;
                }
            }
            return $seen_enemies > 1;
        },
        max         => $spell->minimum_range + 1,

        # if we lost our MR we deserve to die ;)
        allowself   => 1,
        bouncy      => $spell->direction eq 'ray',

        stopper     => sub {
            my $self = shift;
            return 1 if $self->has_friendly;

            if ($is_force_bolt) {
                return 1 if $self->has_monster && $self->monster->is_nymph;
            }

            return 0;
        },
        stopper_max => $spell->maximum_range,

        started_new_direction => sub { $seen_enemies = 0 },
    );

    return if $verboten;
    return unless $direction;

    return TAEB::Action::Cast->new(
        spell     => $spell,
        direction => $direction,
    );
}

sub cast_sleep {
    my $self = shift;

    my $spell = TAEB->find_castable("sleep")
        or return;

    return if $self->sleep_is_blacked_out;

    return unless TAEB->current_level->has_enemies;

    my $direction = TAEB->current_level->radiate(
        sub {
            my $tile = shift;
            return $tile->has_enemy
                && $tile->monster->currently_seen;
        },
        max         => $spell->minimum_range,

        stopper     => sub { shift->has_friendly },
        stopper_max => $spell->maximum_range,

        bouncy    => 1,
        allowself => TAEB->senses->sleep_resistant,
    );
    return unless $direction;

    return TAEB::Action::Cast->new(
        spell     => $spell,
        direction => $direction,
    );
}

sub single_bolt {
    return unless TAEB->current_level->has_enemies;

    my $spell = attack_spell()
        or return;
    my $is_force_bolt = $spell->name eq 'force bolt';

    my $verboten = 0;

    my $direction = TAEB->current_level->radiate(
        sub {
            my ($tile, $distance) = @_;
            return unless $tile->has_enemy;
            return unless $tile->monster->currently_seen;

            # XXX verboten needs to forbid directions
            if ($distance == 1 && $tile->monster->has_possibility('gas spore')) {
                $verboten = 1;
                return;
            }

            return 1;
        },
        max         => $spell->minimum_range,

        # if we lost our MR we deserve to die ;)
        allowself   => 1,
        bouncy      => $spell->direction eq 'ray',

        stopper     => sub {
            my $self = shift;
            return 1 if $self->has_friendly;

            if ($is_force_bolt) {
                return 1 if $self->has_monster && $self->monster->is_nymph;
            }

            return 0;
        },
        stopper_max => $spell->maximum_range,
    );
    return if $verboten;
    return unless $direction;

    return TAEB::Action::Cast->new(
        spell     => $spell,
        direction => $direction,
    );
}

sub melee {
    return unless TAEB->current_level->has_enemies;

    if_adjacent(
        sub {
            my $tile = shift;
            return unless $tile->has_enemy;
            return unless $tile->monster->is_meleeable;

            # don't melee gas spores, bolt them from a distance
            return if $tile->monster->has_possibility('gas spore');

            return 1;
        } => 'melee',
    );
}

sub hunt {
    return unless TAEB->current_level->has_enemies;

    path_to(sub {
        my $tile = shift;

        return $tile->has_enemy
            && $tile->monster->is_meleeable
            && !$tile->monster->is_seen_through_warning
    }, include_endpoints => 1);
}

sub descend {
    my $self = shift;

    return unless TAEB->current_tile->type eq 'stairsdown';

    return if $self->stay_on_level;

    return TAEB::Action::Descend->new;
}

sub eat_inventory {
    return if TAEB->nutrition > 150;

    my @foods = grep { $_->is_safely_edible } TAEB->inventory->find(type => 'food');
    return unless @foods;

    # find and eat the food with the worst nutrition/weight ratio
    my $metric = 'nutrition_per_weight';

    # OR when there are monsters around, with the fewest turns to eat
    $metric = 'time' if find_adjacent(sub { shift->has_enemy });

    my $best = shift @foods;
    for my $food (@foods) {
        # don't eat lizard corpses except as a last resort
        next if $food->subtype eq 'corpse'
             && $food->monster->name eq 'lizard';

        if ($food->$metric < $best->$metric) {
            $best = $food;
        }
    }

    return TAEB::Action::Eat->new(food => $best);
}

sub eat_tile_food {
    my $self = shift;

    return if TAEB->nutrition > 995;
    return if TAEB->current_tile->in_shop;

    my $prefer_sac = $self->offerable_altars && TAEB->nutrition > 100;

    for my $food (grep { $_->type eq 'food' } TAEB->current_tile->items) {
        next unless $food->is_safely_edible(distance => 0);
        next if $food->total_cost;
        next if $prefer_sac && !$self->really_want_food($food);

        if ($food->subtype eq 'corpse' && $food->teleportitis) {
            next unless TAEB->senses->is_teleporting
                     || TAEB->senses->has_teleport_control
                     || TAEB->inventory->find(
                            identity  => 'ring of teleport control',
                            is_cursed => 0,
                        )
                     # XXX ideally TAEB would know this
                     || TAEB->inventory->find("Master Key of Thievery");
        }

        return TAEB::Action::Eat->new(food => $food);
    }

    return;
}

sub to_food {
    my $self = shift;
    return if $self->carried_nutrition > 3000;
    return unless any { $self->want_food($_) }
                  grep { $_->type eq 'food' }
                  TAEB->current_level->items;

    path_to(sub {
        my $tile = shift;
        return any { $self->want_food($_) }
               grep { $_->type eq 'food' }
               $tile->items;
    });
}

sub pickup_goody {
    my $self = shift;

    return unless any { $self->want_goody($_) } TAEB->current_tile->items;

    return TAEB::Action::Pickup->new;
}

sub pickup_food {
    my $self = shift;

    return if $self->carried_nutrition > 3000;
    return unless any { $self->want_food($_) } TAEB->current_tile->items;

    return TAEB::Action::Pickup->new;
}

sub want_food {
    my $self = shift;
    my $food = shift;

    return if $self->carried_nutrition > 3000;
    return unless $food->type eq 'food';
    return unless $food->is_safely_edible;
    return if $food->subtype eq 'corpse' && !$food->permanent;
    return if $food->total_cost;

    return 1;
}

sub really_want_food {
    my $self = shift;
    my $food = shift;

    if ($food->subtype eq 'corpse') {
        return 1 if $food->speed_toggle && !TAEB->is_fast;
        return 1 if $food->telepathy && !TAEB->has_telepathy;
        return 1 if $food->gain_level;
        return 1 if $food->intelligence;
        return 1 if $food->strength;
        # XXX tele, TC
    }

    for my $resist (qw/shock poison fire cold sleep disintegration/) {
        my $prop = "${resist}_resistance";
        my $res  = "${resist}_resistant";
        return 1 if $food->$prop && !TAEB->$res;
    }

    return;
}

sub want_goody {
    my $self = shift;
    my $item = shift;

    return if $item->total_cost;

    # all manner of trinket
    return 1 if $item->match(type => [keys %is_cool_type]);

    return 1 if $item->match('Magicbane');
    return 1 if $item->match('magic marker');

    return 1 if $item->has_tracker
             && $item->tracker->includes_possibility('magic lamp');

    return 1 if $item->match('cloak of magic resistance')
             && !TAEB->inventory->find('cloak of magic resistance');

    return 1 if $item->match('unicorn horn')
             && !TAEB->inventory->find('unicorn horn');

    return 1 if $item->match(identity => ['blindfold', 'towel'])
             && !TAEB->inventory->find(identity => ['blindfold', 'towel']);

    return 0;
}

sub to_unknown_items {
    return unless TAEB->current_level->has_type('unknown_items');
    path_to(sub { shift->has_unknown_items });
}

sub uncurse_goody {
    my $remove_curse = TAEB->find_castable('remove curse')
        or return;
    return if $remove_curse->fail > 50;

    my $goody = TAEB->inventory->find(
        is_cursed => [undef, 1],
    );

    # no need to wield the item if we're skilled or expert
    my $level = TAEB->senses->level_for_skill('clerical');
    if ($level eq 'Skilled' || $level eq 'Expert') {
        return TAEB::Action::Cast->new(spell => $remove_curse);
    }

    my $weapon = TAEB->equipment->weapon || "nothing";

    return [
        TAEB::Action::Wield->new(weapon => $goody),
        TAEB::Action::Cast->new(spell => $remove_curse),
        TAEB::Action::Wield->new(weapon => $weapon),
    ];
}

sub to_goody {
    my $self = shift;
    return unless any { $self->want_goody($_) } TAEB->current_level->items;
    path_to(sub { any { $self->want_goody($_) } shift->items });
}

sub to_stairs {
    my $self = shift;

    return if $self->stay_on_level;

    path_to('stairsdown');
}

sub open_door {
    if_adjacent(closeddoor => sub {
        my $tile = shift;
        if ($tile->is_locked) {
            if (TAEB->current_level->is_minetown) {
                return;
            }

            return 'kick';
        }

        return 'open';
    });
}

sub to_door {
    return unless TAEB->current_level->has_type('closeddoor');

    path_to(sub {
        my $tile = shift;

        return unless $tile->type eq 'closeddoor';

        if ($tile->is_locked && TAEB->current_level->is_minetown) {
            return;
        }

        return 2;
    }, include_endpoints => 1);
}

sub oracle_statues {
    my $self = shift;

    return unless TAEB->current_level->is_oracle;
    return unless any { $_->type eq 'statue' } TAEB->current_level->items;

    my $spell = TAEB->find_spell("force bolt");

    my $direction;
    if (any { $_->type eq 'statue' } TAEB->current_tile->items) {
        $direction = '>';
    }
    else {
        $direction = TAEB->current_level->radiate(
            sub { shift->find_item(type => "statue") },
            max         => $spell->minimum_range,

            stopper     => sub {
                my $self = shift;
                return 1 if $self->has_friendly;
                return 1 if $self->has_monster && $self->monster->is_nymph;
                return 0;
            },
            stopper_max => $spell->maximum_range,
        );
    }

    if (!$direction) {
        return path_to(sub { any { $_->type eq 'statue' } shift->items });
    }

    # restore Pw if needed
    if (!$spell->castable) {
        return TAEB::Action::Search->new(iterations => 20);
    }

    return TAEB::Action::Cast->new(
        spell     => $spell,
        direction => $direction,
    );
}

sub practice_spells {
    my $self = shift;

    return if TAEB->power < 20;
    return if TAEB->power < TAEB->maxpower;

    return $self->practice_nodir("haste self")
        || $self->practice_nodir("identify")
        || $self->practice_nodir("remove curse")
        || $self->practice_nodir("charm monster")
        || $self->practice_nodir("protection")
        || $self->practice_nodir("light")
        || $self->practice_nodir("detect monsters")
        || $self->practice_nodir("detect unseen")
        || $self->practice_nodir("detect treasure")
        || $self->practice_nodir("magic mapping")
        || $self->practice_nodir("cure blindness")
        || $self->practice_nodir("cure sickness")
        || $self->practice_nodir("restore ability")
        || $self->practice_nodir("detect food")
        || $self->practice_nodir("clairvoyance")
        || $self->practice_nodir("confuse monster")
        || $self->practice_nodir("cause fear")
        || $self->practice_force_bolt;
}

sub practice_nodir {
    my $self = shift;
    my $name = shift;

    my $spell = TAEB->find_castable($name)
        or return;

    return TAEB::Action::Cast->new(spell => $spell);
}

sub practice_force_bolt {
    my $force_bolt = TAEB->find_castable("force bolt")
        or return;

    # don't break the items on the ground
    return if TAEB->current_tile->items;

    return TAEB::Action::Cast->new(
        spell     => $force_bolt,
        direction => '>',
    );
}

sub wait_blind {
    return unless TAEB->senses->is_blind;

    return TAEB::Action::Wipe->new if TAEB->senses->is_pie_blind;

    return TAEB::Action::Search->new(iterations => 20);
}

sub explore {
    path_to(sub { shift->unexplored });
}

sub magic_map {
    return if TAEB->current_level->been_magic_mapped;

    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of magic mapping',
        is_cursed => 0,
    ) or return;

    return TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub hang_around_altar {
    my $self = shift;

    my @altars = $self->offerable_altars
        or return;
    my %is_offerable = map { (refaddr $_) => 1 } @altars;

    return TAEB::Action::Search->new(iterations => 20)
        if $is_offerable{refaddr(TAEB->current_tile)};

    path_to(sub { $is_offerable{ refaddr shift } });
}

sub search {
    if_adjacent(
        sub { $_[0]->is_searchable && $_[0]->searched < 30 },
        'search',
    );
}

sub to_search {
    path_to(
        sub { $_[0]->is_searchable && $_[0]->searched < 30 },
        include_endpoints => 1,
    );
}

sub sacrifice_here {
    my $self = shift;

    return unless $self->on_sacable_altar;

    my @corpses = (
        TAEB->inventory->find(subtype => 'corpse'),
        TAEB->current_tile->find_item(subtype => 'corpse'),
    );

    for my $corpse (@corpses) {
        next unless $self->would_sacrifice($corpse);

        return TAEB::Action::Offer->new(
            item => $corpse,
        );
    }

    return;
}

sub shed_carcass {
    my $self = shift;

    my @carcasses;
    for my $corpse (TAEB->inventory->find(subtype => 'corpse')) {
        next if $self->want_food($corpse);
        push @carcasses, $corpse if !$self->would_sacrifice($corpse);
    }

    return unless @carcasses;

    return TAEB::Action::Drop->new(
        items => \@carcasses,
    );
}

sub to_altar {
    my $self = shift;
    my @altars = $self->offerable_altars
        or return;
    my %is_offerable = map { (refaddr $_) => 1 } @altars;

    return unless any { $self->would_sacrifice($_) }
                  TAEB->inventory->find(subtype => 'corpse');

    path_to(sub { $is_offerable{ refaddr shift } });
}

sub pickup_sac {
    my $self = shift;
    return unless $self->offerable_altars;
    return unless any { $self->would_sacrifice($_, 1) }
                  TAEB->current_tile->items;

    return TAEB::Action::Pickup->new;
}

sub to_sac {
    my $self = shift;
    return unless $self->offerable_altars;
    return unless any { $self->would_sacrifice($_, 1) }
                  TAEB->current_level->items;

    path_to(sub { any { $self->would_sacrifice($_, 1) } shift->items });
}

sub find_adjacent {
    my $code = shift;

    my ($tile, $direction);
    TAEB->each_adjacent(sub {
        my ($t, $d) = @_;
        ($tile, $direction) = ($t, $d) if $code->($t, $d);
    });

    return wantarray ? ($tile, $direction) : $tile;
}

sub if_adjacent {
    my $code   = shift;
    my $action = shift;

    if (!ref($code)) {
        my $type = $code;
        $code = sub { shift->type eq $type };
    }

    my ($tile, $direction) = find_adjacent($code);
    return if !$tile;

    $action = $action->($tile, $direction) if ref($action);
    return if !$action;

    my $action_class = "TAEB::Action::\u$action";

    my %args;
    $args{direction} = $direction
        if $action_class->does('TAEB::Action::Role::Direction');

    return $action_class->new(%args);
}

sub path_to {
    my $code = shift;

    if (!ref($code)) {
        my $type = $code;
        $code = sub { shift->type eq $type };
    }

    return TAEB::World::Path->first_match($code, @_);
}

sub dip_bless {
    my $item = shift;
    return if $item->is_blessed;

    my $holy_water = TAEB->inventory->find(
        identity   => 'potion of water',
        is_blessed => 1,
    ) or return;

    return TAEB::Action::Dip->new(
        item => $item,
        into => $holy_water,
    );
}

sub want_item {
    my ($self, $item) = @_;

    return $item->type eq 'spellbook';
}

sub has_adjacent_friendly {
    my $ret;
    TAEB->each_adjacent(sub {
        my ($tile) = @_;
        return unless $tile->has_monster;
        return if $tile->monster->is_enemy;
        $ret = 1;
    });

    return $ret;
}

sub has_adjacent_enemy {
    my $ret;
    TAEB->each_adjacent(sub {
        my ($tile) = @_;
        return unless $tile->has_monster;
        return if !$tile->monster->is_enemy;
        $ret = 1;
    });

    return $ret;
}

sub attack_spell {
    my $force_bolt = TAEB->find_castable("force bolt");
    my $magic_missile = TAEB->find_castable("magic missile");

    # magic missile doesn't beat force bolt til XL8
    if ($force_bolt && $magic_missile) {
        my ($fb_min, $fb_max) = $force_bolt->damage_range;
        my ($mm_min, $mm_max) = $magic_missile->damage_range;
        return $fb_max >= $mm_max ? $force_bolt : $magic_missile;
    }

    return $force_bolt || $magic_missile || undef;
}

sub carried_nutrition {
    (sum map { $_->total_nutrition } TAEB->inventory->find(type => "food")) || 0;
}

subscribe query_pickupitems => sub {
    my $self = shift;
    my $event = shift;

    $event->menu->select(sub {
        my $item = shift->user_data;
        return 1 if $self->want_food($item);
        return 1 if $self->want_goody($item);

        if ($self->offerable_altars) {
            return 1 if $self->would_sacrifice($item, 1);
        }

        return 0;
    });
};

subscribe query_identifyitems => sub {
    my $self = shift;
    my $event = shift;

    # first, prefer items we want to identify
    $event->menu->select(sub {
        my $item = shift->user_data;
        return $self->would_identify($item);
    });

    # next, if needed, just identify anything and everything
    return if $event->menu->selected_items;
    $event->menu->select(sub { 1 });
};

subscribe query_enhance => sub {
    my $self = shift;
    my $event = shift;

    $event->menu->select(sub {
        return 1;
    });
};

sub would_sacrifice {
    my $self = shift;
    my $corpse = shift;
    my $prospective = shift;

    return unless $corpse->match(subtype => 'corpse');

    return if $self->want_food($corpse);
    return if !$corpse->should_sacrifice;
    return if $corpse->total_cost;

    if ($prospective) {
        return if $corpse->monster ne 'acid blob'
               && $corpse->estimate_age > 25;

        # I have no idea what values of inventory are Burdened etc
        # depends on Str, so we should model that in TAEB
        # return if $corpse->weight + TAEB->inventory->weight > xxx;
    }

    return 1;
}

sub offerable_altars {
    my $self = shift;

    my @altars = grep { $_->is_coaligned || !$_->in_temple }
                 TAEB->current_level->has_type('altar');
    return @altars;
}

sub stay_on_level {
    my $self = shift;

    # stick around until we get Magicbane :)
    return 1 if $self->offerable_altars
             && !TAEB->seen_artifact('Magicbane');

    return 0;
}

my @species_genocides = (
    'chameleon',
    'minotaur',
    'soldier ant',
    'leocrotta',
    'disenchanter',
);

my @class_genocides = (
    'a',
    'n',
    'L',
    'h',
    ';',
    'T',
);

sub respond_genocide_species {
    return shift(@species_genocides) . "\n";
}

sub respond_genocide_class {
    return shift(@class_genocides) . "\n";
}

my @wishes = (
    '2 blessed scrolls of charging' => {
        avoid => sub {
            # only wish for b?oC if we used a wand to get this wish
            my $action = TAEB->action;
            return "not a wand wish" unless $action->isa('TAEB::Action::Zap')
                                         || $action->isa('TAEB::Action::Engrave');

            my $wand = $action->isa('TAEB::Action::Zap') ? $action->wand
                                                         : $action->engraver;

            return "already recharged wand"
                if $wand->times_recharged;

            # don't bother if we already have a scroll of charging
            return "have b?oC" if TAEB->has_item(
                identity => 'scroll of charging',
                is_blessed => 1,
            );

            # don't bother if we have charging and can bless it
            return "have uc?oC and !oHW" if TAEB->has_item(
                identity    => 'scroll of charging',
                is_uncursed => 1,
            ) && TAEB->has_item(
                identity   => 'potion of water',
                is_blessed => 1,
            );

            # XXX if our charging is cursed (or unknown) and we have 2 holy water, still don't need to wish for it, but that'll probably be rare

            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            return unless $item->has_tracker; # has it already been IDed?
            $item->tracker->identify_as('scroll of charging');
        },
    },
    'blessed fixed greased Master Key of Thievery' => {
        avoid => sub {
            return "would die from artifact blast" if TAEB->hp <= 20;
            return "already seen MKoT" if TAEB->seen_artifact('Master Key of Thievery');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
        },
    },
    'blessed fixed greased +3 silver dragon scale mail' => {
        avoid => sub {
            return "have DSM" if TAEB->inventory->find('silver dragon scale mail');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
        },
    },
    'blessed fixed greased +3 speed boots' => {
        avoid => sub {
            return "have speed boots" if TAEB->inventory->find('speed boots');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
            return unless $item->has_tracker;
            $item->tracker->identify_as("speed boots");
        },
    },

    'blessed fixed greased +3 helm of brilliance' => {
        avoid => sub {
            return "have helm of brilliance" if TAEB->inventory->find('helm of brilliance');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
            return unless $item->has_tracker;
            $item->tracker->identify_as("helm of brilliance");
        },
    },

    'blessed fixed greased ring of conflict' => {
        avoid => sub {
            return "have ring of conflict" if TAEB->inventory->find('ring of conflict');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
            return unless $item->has_tracker;
            $item->tracker->identify_as("ring of conflict");
        },
    },

    'blessed fixed greased +3 gauntlets of dexterity' => {
        avoid => sub {
            return "have gauntlets of dexterity" if TAEB->inventory->find('gauntlets of dexterity');
            return;
        },
        identify => sub {
            my $item = shift;
            $item->is_blessed(1);
            $item->is_greased(1);
            return unless $item->has_tracker;
            $item->tracker->identify_as("gauntlets of dexterity");
        },
    },

    'uncursed magic marker' => {
        avoid    => sub { return },
        identify => sub {
            my $item = shift;
            $item->is_uncursed(1);
        },
    },
);

sub respond_wish {
    my $self = shift;

    for (my $i = 0; $i < @wishes; $i += 2) {
        my ($wish, $handlers) = @wishes[$i, $i+1];
        my $avoid_reason = $handlers->{avoid}->();
        if ($avoid_reason) {
            TAEB->log->ai("Not wishing for '$wish' because $avoid_reason");
            next;
        }

        $self->last_wish($wish);

        return "$wish\n";
    }
}

subscribe step => sub {
    my $self = shift;
    $self->_clear_last_wish;
};

subscribe got_item => sub {
    my $self = shift;
    my $event = shift;

    my $item = $event->item;

    if (my $last_wish = $self->last_wish) {
        for (my $i = 0; $i < @wishes; $i += 2) {
            my ($wish, $handlers) = @wishes[$i, $i+1];
            next unless $wish eq $last_wish;

            TAEB->log->ai("Identifying $item using the $wish handler");

            $handlers->{identify}->($item);
            return;
        }

        TAEB->log->ai("No handler for wish $last_wish!", level => "error");
    }
};

sub botl_modes {
    magus => {
        description => __PACKAGE__,
        botl => sub {
            my $currently = TAEB->currently;
            $currently =~ s/_/ /g;
            $currently = '' if $currently eq '?';
            return $currently;
        },
        status => sub {
            my $self = TAEB->ai;

            my @pieces;

            push @pieces, 'H:' . TAEB->hp
                if TAEB->hp < TAEB->maxhp;

            push @pieces, 'P:' . TAEB->power
                if TAEB->power < TAEB->maxpower;

            push @pieces, 'N:' . TAEB->nutrition . '+' . $self->carried_nutrition;

            push @pieces, 'A:' . TAEB->ac;
            push @pieces, 'X' . TAEB->level;

            push @pieces, 'T:' . TAEB->turn;

            push @pieces, 'S:' . TAEB->score
                if TAEB->has_score;

            my @special;
            push @special, 'R'
                if TAEB->equipment->is_wearing_ring("ring of regeneration");
            push @special, 'C'
                if TAEB->equipment->is_wearing_ring("ring of conflict");
            push @special, 'SD'
                if TAEB->equipment->is_wearing_ring("ring of slow digestion");

            push @special, 'PR'
                if TAEB->equipment->is_wearing_ring("ring of poison resistance");

            push @special, 'SM'
                if TAEB->current_tile # :(
                && TAEB->current_tile->find_item("scroll of scare monster");

            if (TAEB->senses->is_very_fast) {
                push @special, 'VF';
            }
            elsif (TAEB->senses->is_fast) {
                push @special, 'F';
            }

            push @special, 'I'
                if TAEB->senses->is_invisible;

            push @pieces, '[' . (join ' ', @special) . ']'
                if @special;

            my $status = join ' ', @pieces;

            # time on the RHS
            my $time = TAEB->display->step_time;
            $status .= ' ' x (80 - length($status) - length($time));
            $status .= $time;

            return $status;
        },
    },
}

@METHODS = sort __PACKAGE__->meta->get_all_method_names;

1;

