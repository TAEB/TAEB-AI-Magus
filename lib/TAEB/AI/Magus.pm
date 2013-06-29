package TAEB::AI::Magus;
use Moose;
use TAEB::Util 'uniq';
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

my @behaviors = (qw/
    pray
    bolt
    melee
    hunt
    eat_here
    to_item
    buff_.*
    descend
    to_stairs
    open_door
    to_door
    explore
    search
/);

sub next_action {
    my $self = shift;

    my $queued = $self->queue_manager->next_queued_action;
    return $queued if $queued;

    my @methods = __PACKAGE__->meta->get_all_method_names;

    for my $behavior (@behaviors) {
        for my $method (grep { /^$behavior$/ } @methods) {
            my $action = $self->$method
                or next;

            $self->currently($method);

            if (ref($action) eq 'ARRAY') {
                $self->queue_manager->enqueue_actions(@$action);
                return $self->queue_manager->next_queued_action;
            }

            return $action;
        }
    }

    $self->currently('to_search');
    return $self->to_search;
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

sub buff_great_potion {
    my $potion = TAEB->inventory->find(
        identity   => [
            'potion of see invisible',
            'potion of gain ability',
        ],
        is_blessed => 1,
    ) || TAEB->inventory->find(
        identity => [
            'potion of gain ability',
        ],
        is_cursed => 0,
    ) or return;

    return dip_bless($potion) || TAEB::Action::Quaff->new(
        from => $potion,
    );
}

sub buff_slow_digestion {
    return if TAEB->equipment->has_left_sd
           || TAEB->equipment->has_right_sd;

    my $ring = TAEB->inventory->find(
        identity  => 'ring of slow digestion',
        is_cursed => 0,
    ) or return;

    return TAEB::Action::Wear->new(item => $ring);
}

sub pray {
    return unless TAEB::Action::Pray->is_advisable;

    return unless TAEB->nutrition < 0
               || TAEB->in_pray_heal_range;

    return TAEB::Action::Pray->new;
}

sub bolt {
    my $force_bolt = TAEB->find_castable("force bolt")
        or return;

    my $direction = TAEB->current_level->radiate(
        sub { shift->has_enemy },
        max         => $force_bolt->minimum_range,

        stopper     => sub { shift->has_friendly },
        stopper_max => $force_bolt->maximum_range,
    );
    return unless $direction;

    return TAEB::Action::Cast->new(
        spell     => $force_bolt,
        direction => $direction,
    );
}

sub melee {
    if_adjacent(
        sub {
            my $tile = shift;
            $tile->has_enemy && $tile->monster->is_meleeable
        } => 'melee',
    );
}

sub hunt {
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

sub explore {
    path_to(sub { shift->unexplored });
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

1;

