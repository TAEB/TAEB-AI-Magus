package TAEB::AI::Magus::Goal::MakeStash;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterSokoban' }

1;

