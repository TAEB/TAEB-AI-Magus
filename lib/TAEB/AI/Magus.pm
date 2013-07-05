package TAEB::AI::Magus;
use Moose;
use TAEB::Util 'uniq', 'all', 'any';
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

my @behaviors = (qw/
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
    take_off_regen
    wait_scare_monster
    hunt
    eat_here
    to_item
    buff_.*
    put_on_pois_res
    descend
    to_stairs
    open_door
    to_door
    practice_spells
    explore
    magic_map
    search
/);

sub next_action {
    my $self = shift;

    my $queued = $self->queue_manager->next_queued_action;
    if ($queued) {
        $self->currently($self->queue_manager->currently);
        return $queued;
    }

    my @methods = __PACKAGE__->meta->get_all_method_names;

    for my $behavior (@behaviors) {
        for my $method (grep { /^$behavior$/ } @methods) {
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

sub buff_polypotion_spellbook {
    my $polymorph = TAEB->inventory->find("potion of polymorph")
        or return;

    # prefer blessed books since you're guaranteed to learn them
    my @books = uniq (
        TAEB->inventory->find(type => 'spellbook', is_blessed => 1),
        TAEB->inventory->find(type => 'spellbook', is_cursed => 0),
    );

    for my $book (@books) {
        my $identity = $book->identity;

        # don't polymorph unidentified spellbooks
        next unless $identity;

        # don't polymorph spellbooks we haven't learned yet
        unless ($identity eq "spellbook of blank paper") {
            my $spell_name = $book->spell;
            next unless TAEB->spells->find($spell_name);
        }

        return TAEB::Action::Dip->new(
            item => $book,
            into => $polymorph,
        );
    }

    return;
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

sub buff_reading_unknown_spellbook {
    my @books = TAEB->inventory->find(
        type      => 'spellbook',
        identity  => undef,
        is_cursed => 0,
    );

    for my $book (@books) {
        next if $book->difficult_for_level >= TAEB->level;

        return TAEB::Action::Read->new(
            item => $book,
        );
    }
    return;
}

sub buff_enchant_weapon {
    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of enchant weapon',
        is_cursed => 0,
    ) or return;

    my $weapon = TAEB->equipment->weapon or return;

    return if ($weapon->numeric_enchantment||0) > 5;

    return dip_bless($scroll) || TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub buff_enchant_armor {
    my $scroll = TAEB->inventory->find(
        identity  => 'scroll of enchant armor',
        is_cursed => 0,
    ) or return;

    # XXX make sure our armor's lined up right...

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

    return TAEB::Action::Pray->new;
}

sub heal_self {
    return if TAEB->hp * 2 > TAEB->maxhp;

    my $spell = TAEB->find_castable("extra healing") || TAEB->find_castable("healing");
    if ($spell) {
        return TAEB::Action::Cast->new(
            spell     => $spell,
            direction => '.',
        );
    }

    # XXX potion

    return;
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
    return unless TAEB->current_tile->type eq 'stairsdown';

    return TAEB::Action::Descend->new;
}

sub eat_here {
    return if TAEB->nutrition > 995;
    return if TAEB->current_tile->in_shop;

    for my $food (grep { $_->type eq 'food' } TAEB->current_tile->items) {
        next unless $food->is_safely_edible(distance => 0);

        return TAEB::Action::Eat->new(food => $food);
    }

    return;
}

sub to_item {
    return unless TAEB->current_level->has_type('interesting');
    path_to(sub { shift->is_interesting });
}

sub to_stairs {
    path_to('stairsdown');
}

sub open_door {
    if_adjacent(closeddoor => sub {
        return 'kick' if shift->is_locked;
        return 'open';
    });
}

sub to_door {
    path_to('closeddoor', include_endpoints => 1);
}

sub practice_spells {
    my $self = shift;

    return if TAEB->power < 20;
    return if TAEB->power < TAEB->maxpower;

    return $self->practice_haste_self
        || $self->practice_force_bolt;
}

sub practice_haste_self {
    my $spell = TAEB->find_castable("haste self")
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

1;

