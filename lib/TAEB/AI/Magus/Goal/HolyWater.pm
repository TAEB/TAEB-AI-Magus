package TAEB::AI::Magus::Goal::HolyWater
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'CoalignedAltar' }

1;

