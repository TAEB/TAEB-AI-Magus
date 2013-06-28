package TAEB::AI::Magus::Goal::CoalignedAltar;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub met_when {
    my @altars = TAEB->dungeon->tiles_of_type('altar');
    return any { $_->is_coaligned } @altars;
}

1;

