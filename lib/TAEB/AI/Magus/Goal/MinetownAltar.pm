package TAEB::AI::Magus::Goal::MinetownAltar;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterMinetown' }

sub met_when {
    my $level = TAEB->current_level;
    return 0 unless $level->is_minetown;
    return any { defined($_->align) } $level->tiles_of('altar');
}

1;

