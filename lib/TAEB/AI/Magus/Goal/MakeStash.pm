package TAEB::AI::Magus::Goal::MakeStash;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterSokoban' }

1;

