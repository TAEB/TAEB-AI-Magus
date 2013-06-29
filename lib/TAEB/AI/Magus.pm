package TAEB::AI::Magus;
use Moose;
extends 'TAEB::AI';

use TAEB::AI::Magus::GoalManager;
use TAEB::Util 'uniq';

has manager => (
    is      => 'ro',
    isa     => 'TAEB::AI::Magus::GoalManager',
    default => sub { TAEB::AI::Magus::GoalManager->new },
    handles => ['current_goal'],
);

my @behaviors = (qw/
    pray
    bolt
    melee
    hunt
    to_item
    buff_.*
    descend
    to_stairs
    open_door
    to_door
    explore
    search
/);

# The framework calls this method on the AI object to determine what action to
# do next. An action is an instance of TAEB::Action, which is basically a handy
# object wrapper around a NetHack command like "s" for search.
sub next_action {
    my $self = shift;

    my @methods = __PACKAGE__->meta->get_all_method_names;

    # Try each of these behaviors (which are methods) in order...
    for my $behavior (@behaviors) {
        for my $method (grep { /^$behavior$/ } @methods) {
            my $action = $self->$method
                or next;

            # "currently" is for reporting what we're doing on the second-to-last
            # line of the TAEB display. Optional but you should set it anyway.
            $self->currently($behavior);

            return $action;
        }
    }

    # We must be trapped! Search for a secret door. This is a nice fallback
    # since you can search indefinitely.
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

    return TAEB::Action::Read->new(
        item => $scroll,
    );
}

sub buff_see_invisible {
    my $potion = TAEB->inventory->find(
        identity   => 'potion of see invisible',
        is_blessed => 1,
    ) or return;

    return TAEB::Action::Quaff->new(
        from => $potion,
    );
}

sub pray {
    # This returns false if we prayed recently, or our god is angry, etc.
    return unless TAEB::Action::Pray->is_advisable;

    # Only pray if we're low on nutrition or health.
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

# Find an adjacent enemy and swing at it.
sub melee {
    if_adjacent(
        sub {
            my $tile = shift;
            $tile->has_enemy && $tile->monster->is_meleeable
        } => 'melee',
    );
}

# Find an enemy on the level and hunt it down.
sub hunt {
    path_to(sub {
        my $tile = shift;

        return $tile->has_enemy
            && $tile->monster->is_meleeable
            && !$tile->monster->is_seen_through_warning
    }, include_endpoints => 1);
}

# If we're on stairs then descend.
sub descend {
    return unless TAEB->current_tile->type eq 'stairsdown';

    return TAEB::Action::Descend->new;
}

sub to_item {
    return unless TAEB->current_level->has_type('interesting');
    path_to(sub { shift->is_interesting });
}

# If we see stairs, then go to them.
sub to_stairs {
    path_to('stairsdown');
}

# If there's an adjacent closed door, try opening it. If it's locked, kick it
# down.
sub open_door {
    if_adjacent(closeddoor => sub {
        return 'kick' if shift->is_locked;
        return 'open';
    });
}

# If we see a closed door, then go to it.
sub to_door {
    path_to('closeddoor', include_endpoints => 1);
}

# If there's an unexplored tile (tracked by the framework), go to it.
sub explore {
    path_to(sub { shift->unexplored });
}

# If there's an unsearched tile next to us, search.
sub search {
    if_adjacent(
        sub { $_[0]->is_searchable && $_[0]->searched < 30 },
        'search',
    );
}

# If there's an unsearched tile, go to it.
sub to_search {
    path_to(
        sub { $_[0]->is_searchable && $_[0]->searched < 30 },
        include_endpoints => 1,
    );
}

# These helper functions make our behavior code far more concise and
# declarative.

# find_adjacent finds and adjacent tile that satisfies some predicate. It takes
# a coderef and returns the (tile, direction) corresponding to the adjacent
# tile that returned true for the predicate.
sub find_adjacent {
    my $code = shift;

    my ($tile, $direction);
    TAEB->each_adjacent(sub {
        my ($t, $d) = @_;
        ($tile, $direction) = ($t, $d) if $code->($t, $d);
    });

    return wantarray ? ($tile, $direction) : $tile;
}

# if_adjacent takes a predicate and an action name. If the predicate returns
# true for any of the adjacent tiles, then the action will be instantiated and
# returned.
sub if_adjacent {
    my $code   = shift;
    my $action = shift;

    # Allow caller to pass in a tile type name to check for an adjacent tile
    # with that type.
    if (!ref($code)) {
        my $type = $code;
        $code = sub { shift->type eq $type };
    }

    my ($tile, $direction) = find_adjacent($code);
    return if !$tile;

    # If they pass in a coderef for action, then they need to do some additional
    # processing based on tile type. Let them decide an action name.
    $action = $action->($tile, $direction) if ref($action);

    my $action_class = "TAEB::Action::\u$action";

    # We only want to pass in a direction if the action cares about direction.
    # Actions that care about direction do the TAEB::Action::Role::Direction
    # "role". Kind of like a Java interface, but more awesome.
    my %args;
    $args{direction} = $direction
        if $action_class->does('TAEB::Action::Role::Direction');

    return $action_class->new(%args);
}

# path_to takes a predicate (and optional arguments to pass to the pathfinder)
# and finds the closest tile that satisfies that predicate. If there is such a
# tile, then a Path will be returned.
# If you need to find a path adjacent to an unwalkable tile, then pass in
# include_endpoints => 1.
sub path_to {
    my $code = shift;

    # Allow caller to pass in a tile type name to find a tile with that type.
    if (!ref($code)) {
        my $type = $code;
        $code = sub { shift->type eq $type };
    }

    # TAEB will inflate a path into a Move action for us
    return TAEB::World::Path->first_match($code, @_);
}

1;

