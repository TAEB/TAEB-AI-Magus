package TAEB::AI::Magus::Goal::EnterMines;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub met_when {
    my $branch = TAEB->current_level->branch;
    return ($branch || '') eq 'Mines';
}

1;

