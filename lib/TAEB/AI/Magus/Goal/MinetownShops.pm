package TAEB::AI::Magus::Goal::MinetownShops;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterMinetown' }

1;

