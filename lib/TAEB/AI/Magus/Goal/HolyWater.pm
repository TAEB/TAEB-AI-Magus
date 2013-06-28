package TAEB::AI::Magus::Goal::HolyWater
use Moose;
use TAEB::Util 'any';
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'CoalignedAltar' }

1;

