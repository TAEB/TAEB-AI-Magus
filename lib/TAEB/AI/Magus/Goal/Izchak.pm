package TAEB::AI::Magus::Goal::Izchak;
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterMinetown' }

1;

